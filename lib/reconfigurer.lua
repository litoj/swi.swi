---@diagnostic disable: invisible
---@module 'sai.lib.reconfigurer'

local e = require 'sai.api.eventloop'
local U = require 'sai.lib.utils'

---@overload fun(apply:fun(self:sai.lib.reconfigurer)|boolean)
---@class sai.lib.reconfigurer: sai.api.proxy
---@field protected _special {[string]:sai.lib.reconfigurer.special} custom behaviour of the api's special fields
---@field protected _enabled boolean
local M = {
	save_user_changes = false, --- update setting override values to current state before restoring
}

---@class sai.lib.reconfigurer.sai: sai.lib.reconfigurer,sai
---@field eventloop sai.lib.reconfigurer.eventloop
---@field text sai.lib.reconfigurer.text
---@field imagelist sai.imagelist|fun(apply:fun(l:sai.imagelist))
---@field viewer sai.viewer|fun(apply:fun(v:sai.viewer))
---@field slideshow sai.slideshow|fun(apply:fun(s:sai.slideshow))
---@field gallery sai.gallery|fun(apply:fun(g:sai.gallery))

---@overload fun(suball:sai.eventloop.hook[])
---@class sai.lib.reconfigurer.eventloop: sai.lib.reconfigurer,sai.eventloop
---@field protected _new {[hook_cfg]:1} hooks to register
---@field protected _old {[hook_cfg]:1} removed hooks to put back when the override gets disabled
---@field protected _filter {[sai.eventloop.filter.opts]:1} params to unsub existing events by

---@overload fun(apply:fun(self:sai.api.text)|boolean)
---@class sai.lib.reconfigurer.text: sai.lib.reconfigurer,sai.api.text
---@field protected _enforced {enabled?:true, status_timeout?:true} the user-written values that outlive the locations the machinery armed them for; machinery defaults are absent

---Compact one-line description of a hook or an unsubscribe filter entry.
local function hook_str(h)
	local ev = type(h.event) == 'table' and table.concat(h.event, ',') or h.event or '*'
	local sel = h.match or h.pattern or h.group or h.id
	return ('%s=%s'):format(ev, tostring(sel or ''))
end

local elmeta = {
	__index = function(_, idx) error('sai.lib.reconfigurer.eventloop does not support index: ' .. idx) end,
	---@diagnostic disable-next-line: redefined-local
	__call = function(self, enable)
		if type(enable) == 'table' then
			for _, v in ipairs(enable) do
				self.subscribe(v)
			end
			return
		end

		if enable == self._enabled then return false end
		self._enabled = enable

		if enable then
			for h, _ in pairs(self._new) do
				e.subscribe(h)
			end

			for f, _ in pairs(self._filter) do
				for h, _ in pairs(e.find_all(f)) do
					self._old[h] = 1
				end
				e.unsubscribe(f)
			end
		else -- disable
			for h, _ in pairs(self._new) do
				e.unsubscribe { id = h }
			end

			for h, _ in pairs(self._old) do
				e.subscribe(h)
			end
			self._old = {}
		end
	end,

	__tostring = function(self)
		local hooks, filters = {}, {}
		for h in pairs(self._new) do
			hooks[#hooks + 1] = hook_str(h)
		end
		for f in pairs(self._filter) do
			filters[#filters + 1] = hook_str(f)
		end
		return U.tbl_to_str { hooks = hooks, filters = filters }
	end,
}

---@param self sai.lib.reconfigurer.eventloop|sai.lib.reconfigurer?
---@return sai.lib.reconfigurer.eventloop
function M.new_evloop(self)
	---@type sai.lib.reconfigurer.eventloop
	---@diagnostic disable-next-line: missing-fields
	self = self or { _enabled = false }
	self._new = {}
	self._old = {}
	self._filter = {}

	self.subscribe = function(h)
		self._new[h] = 1
		if self._enabled then e.subscribe(h) end
		return h
	end

	self.unsubscribe = function(f)
		if f.id and self._new[f.id] then -- change the applied preset only if directly asking for it
			self._new[f.id] = nil
		else
			self._filter[f] = 1
		end
		if self._enabled then e.unsubscribe(f) end
	end

	self.find_all = function(f)
		local h = e._hooks
		-- the registry swap is the whole point: let find_all see only this
		-- preset's hooks, in a plain id-keyed table the typed registry is not
		---@diagnostic disable-next-line: inject-field, assign-type-mismatch
		e._hooks = self._new
		local ret = e.find_all(f)
		---@diagnostic disable-next-line: inject-field
		e._hooks = h
		return ret
	end

	return setmetatable(self, elmeta)
end

---Special field behaviour: some overrides cannot be expressed as a plain
---value swap, so a field can register functions around the swap.
---@class sai.lib.reconfigurer.special
---@field avail? fun(self:sai.lib.reconfigurer):boolean is the field settable in the current state
---@field apply? fun(self:sai.lib.reconfigurer, override:sai.lib.registry.record) owns the whole application including the value write
---@field restore? fun(self:sai.lib.reconfigurer, override:sai.lib.registry.record, old:any, field:string, top:boolean) owns the whole restore; only `top` may write the field, the rest just undo their own side effects; old is nil when never applied

local vars = require('sai.lib.registry').vars

local function derived_field(mode, default)
	return {
		-- the current view can only be changed while in its mode
		avail = function() return sai.mode == mode end,
		-- put the snapshot back; a view we never applied has nothing to
		-- undo, it re-derives from its default instead
		restore = function(self, _, old, field, top)
			if not top then return end
			if old == nil then
				---Our default override when we have one, else re-set the
				---current value so the api re-derives from it
				local default_override = vars[self.super][default][self]
				if default_override then
					self.super[default] = default_override.old
				else
					self.super[default] = self.super[default]
				end
			else
				self.super[field] = old
			end
		end,
	}
end

---Undo one field override: remove this layer's record from the stack. An
---upper layer receives the restore target instead of a write; without one
---the restore value gets written back (the special owns the write). A var
---that never got applied has nothing to undo - only its special may act.
---@param self sai.lib.reconfigurer
---@param field string
---@param purge? boolean also remove the var itself: a left-over var would re-apply on a later enable
local function release(self, field, purge)
	local override = vars[self.super][field][self]
	if not override then return end

	-- a mode-driven restore is machinery, not a user option change: mute
	-- the option printers around it
	local muted = e.ignore_opts
	e.ignore_opts = true

	local old = vars[self.super][field]:set(self)
	local special = self._special[field]
	if old ~= nil then -- we were on top: the restore value gets written back
		if special and special.restore then
			special.restore(self, override, old, field, true)
		else
			if self.save_user_changes then override.new = self.super[field] end
			self.super[field] = old
		end
	elseif override.old ~= nil then -- an upper layer received the restore target
		if special and special.restore then special.restore(self, override, override.old, field, false) end
	elseif special and special.restore then -- never applied: only the special may act
		special.restore(self, override, nil, field, true)
	end

	e.ignore_opts = muted
	-- a reentrant takeover during our restores (an event handler borrowing
	-- the field back through us) owns the var again: leave it whole
	if vars[self.super][field][self] then return end
	if purge then
		self._enforced[field] = nil
	else -- the var survives for a re-apply on a later enable
		override.old = nil
		vars[self.super][field][self] = override
	end
end

-- true while the machinery writes a display default (the layer flag a block
-- arms, the pin a status sets): the override stores that as not enforced
local arming = false

local special_fields = {
	['sai.viewer'] = {
		position = derived_field('viewer', 'default_position'),
		scale = derived_field('viewer', 'default_scale'),
	},
	['sai.slideshow'] = {
		position = derived_field('slideshow', 'default_position'),
		scale = derived_field('slideshow', 'default_scale'),
	},
	['sai.text'] = {
		status = {
			-- the status write arms the app's expiry with the current
			-- timeout: pin 0 first, else an inherited delay clears our
			-- message (a timeout var of ours manages the expiry itself)
			apply = function(self, override)
				local timeout_var = vars[self.super].status_timeout[self]
				if not (timeout_var and timeout_var.new ~= 0) then
					arming = true
					self.status_timeout = 0
					arming = false
				end
				self.super.status = override.new
			end,
			-- the status comes back only if it was permanent: a timed one is
			-- long gone, restoring it would resurrect a dead message
			restore = function(self, _, old, _, top)
				if old ~= nil and top then
					local timeout_var = vars[self.super].status_timeout[self]
					local timeout = timeout_var and timeout_var.old or self.super.status_timeout
					-- a space, not '': an empty write does not repaint (a
					-- forgotten redraw), a blank one does
					self.super.status = timeout == 0 and old or ' '
				end
				-- a re-taken status still needs its pin
				local status_var = vars[self.super].status[self]
				if status_var and status_var.old ~= nil then return end
				-- the pin we armed as a default has nothing left to serve
				-- once our status is gone
				local timeout_var = vars[self.super].status_timeout[self]
				if timeout_var and not self._enforced.status_timeout then release(self, 'status_timeout', true) end
			end,
		},
		status_timeout = {
			-- undo only our own value: a late direct write must survive the
			-- release, the same principle as the block emptiers
			restore = function(self, override, old, _, top)
				if old == nil or not top then return end
				if self.super.status_timeout ~= override.new then return end
				-- a live status keeps the pin (it is the config default);
				-- _enabled gates a tree disable out of it
				local status_var = vars[self.super].status[self]
				self.super.status_timeout = self._enabled and status_var and status_var.old ~= nil and 0 or old
			end,
		},
		enabled = {
			-- our display ends: drop the emptiers so they cannot re-apply
			-- later (the user may have enabled the layer themselves since)
			restore = function(self, _, old, _, top)
				if old == false then
					-- keep it up while another live layer still needs it
					local held = false
					for _, record in ipairs(vars[self.super].enabled) do
						if record.new == true then
							held = true
							break
						end
					end
					-- our own content is the config default and keeps the
					-- layer up; _enabled gates a tree disable out of it
					local own = false
					if self._enabled then
						for _, location in ipairs(U.block_positions) do
							local v = vars[self.super][location][self]
							if v and v.old ~= nil and next(v.new or {}) then
								own = true
								break
							end
						end
					end
					if top then self.super.enabled = held or own end
					if not own then
						for _, location in ipairs(U.block_positions) do
							local emptier = vars[self.super][location][self]
							-- only the emptiers: our own content vars must survive
							if emptier and not next(emptier.new or {}) then
								-- release + purge: undo our blank without a re-apply later
								release(self, location, true)
							end
						end
					end
				elseif top and old ~= nil then
					-- we never brought the layer up: the write is the whole restore
					self.super.enabled = old
				end
			end,
		},
	},
}

---A block var of ours is either our own content, or an emptier: an empty
---value put over a stale block when taking the layer over.
---@param location block_position_t
---@return sai.lib.reconfigurer.special
local function block_field(location)
	return {
		-- bring the layer up (unless we manage it) and blank the locations
		-- nobody else shows on: their content predates the takeover and
		-- would flash stale. The emptiers are pre-created so their blank
		-- writes cannot re-enter this arming logic.
		apply = function(self, override)
			-- what we took over from: the arming var's `old` while applied,
			-- the live state while it waits for its re-apply
			local enabled_var = vars[self.super].enabled[self]
			local from_off = enabled_var and enabled_var.old
			if from_off == nil then from_off = self.super.enabled end
			self.super[location] = override.new
			if not enabled_var then
				arming = true
				self.enabled = true
				arming = false
			end
			if from_off ~= false then return end -- live content: not ours to clear

			local emptiers = {}
			for _, other in ipairs(U.block_positions) do
				if
					other ~= location
					and not vars[self.super][other][self]
					and #vars[self.super][other] == 0
					and next(self.super[other] or {})
				then
					-- pre-created so the blank write below cannot re-enter this arming logic
					vars[self.super][other][self] = { new = {} }
					emptiers[#emptiers + 1] = other
				end
			end
			for _, other in ipairs(emptiers) do
				arming = true
				self[other] = {}
				arming = false
			end
		end,
		-- only our own content or blank is ours to undo: another owner's
		-- must survive us
		restore = function(self, override, old, _, top)
			if old ~= nil and top then
				if next(override.new or {}) or not next(self.super[location] or {}) then self.super[location] = old end
			end
			-- a re-taken location still needs its layer flag
			local v = vars[self.super][location][self]
			if v and v.old ~= nil then return end
			-- the layer flag we armed as a default has nothing left to serve
			-- once no location of ours is on display anymore
			local enabled_var = vars[self.super].enabled[self]
			if enabled_var and not self._enforced.enabled then
				for _, other in ipairs(U.block_positions) do
					local v = vars[self.super][other][self]
					if v and v.old ~= nil and next(v.new or {}) then return end
				end
				release(self, 'enabled', true)
			end
		end,
	}
end

for _, location in ipairs(U.block_positions) do
	special_fields['sai.text'][location] = block_field(location)
end

---Is the field settable in the tree's current state
---@param self sai.lib.reconfigurer
---@param field string
---@return boolean
function M:_avail(field)
	local special = self._special[field]
	return not special or not special.avail or special.avail(self)
end

-- TODO: make a separate global setting for custom mode name and obj to allow F1 be generic and work
-- for truly every mode + also show only settings for that mode -> no more tabs
---Requires .super (faked api)
---@param self {super:sai.lib.backer, _enabled?:boolean}
---@return self
function M:new()
	self._enabled = self._enabled or false
	if self.super._path == 'sai.eventloop' then return M.new_evloop(self) end

	---@cast self sai.lib.reconfigurer
	for name, method in pairs(M) do
		if name:sub(1, 2) ~= '__' and name:sub(1, 3) ~= 'new' then self[name] = method end
	end
	self._enforced = {}
	self._special = special_fields[self.super._path] or {}

	if self.super._path == 'sai' then
		self.eventloop = M.new_evloop()
		self.eventloop.subscribe {
			event = { 'ModeChangedPre', 'ModeChanged' },
			callback = function(ev)
				local mode_cfg = rawget(self, ev.mode)
				-- enable/disable the vars in the active mode
				-- because some vars may not be changeable while in other modes (viewer.scale, position...)
				-- FIXME: enabling is now for all modes, meaning scale etc won't get written when in gallery
				if mode_cfg and self._enabled then mode_cfg(ev.event == 'ModeChanged') end
			end,
		}
	end

	return setmetatable(self, M)
end

function M:__index(field)
	local subapi = rawget(self.super, field)
	if not getmetatable(subapi) then return vars[self.super][field][self] end

	rawset(self, field, M.new { super = subapi, _enabled = self._enabled })
	return self[field]
end
function M:__newindex(field, value)
	if value == nil then -- reset the var
		local override = vars[self.super][field][self]
		if override and self._enabled and self:_avail(field) and override.old ~= nil then
			-- the purge inside respects a reentrant re-takeover
			release(self, field, true)
		else
			vars[self.super][field]:set(self) -- parked: never applied, nothing to restore
			self._enforced[field] = nil
		end
	else
		local override = { new = value }
		if not arming and (field == 'enabled' or field == 'status_timeout') then self._enforced[field] = true end
		if self._enabled and self:_avail(field) then
			local special = self._special[field]
			-- a mode-driven write is machinery, not a user option change:
			-- mute the option printers around it
			local muted = e.ignore_opts
			e.ignore_opts = true
			override.old = self.super[field]
			vars[self.super][field]:set(self, override)
			if special and special.apply then
				special.apply(self, override)
			else
				self.super[field] = value
			end
			e.ignore_opts = muted
		else -- cannot apply it yet: park the record for a later enable
			vars[self.super][field][self] = override
		end
	end
end
function M:__call(enable)
	if type(enable) == 'function' then return enable(self) end

	if enable == self._enabled then return false end
	self._enabled = enable

	if enable then
		-- the re-apply is mode machinery: keep the option printers muted
		local muted = e.ignore_opts
		e.ignore_opts = true
		for field, stack in pairs(vars[self.super]) do
			local parked = stack[self]
			if parked and self:_avail(field) then
				local special = self._special[field]
				-- a fresh record: an in-place old update would corrupt the
				-- kept restore target of an applied one (an un-avail field
				-- can survive a disable)
				local override = { new = parked.new, old = self.super[field] }
				stack:set(self, override)
				if special and special.apply then
					special.apply(self, override)
				else
					self.super[field] = override.new
				end
			end
		end
		e.ignore_opts = muted
	else
		for field, stack in pairs(vars[self.super]) do
			if stack[self] and self:_avail(field) then release(self, field) end
		end
	end

	-- the user's sub-configs are override trees of their own: they follow this one's state
	-- TODO: what if sai.formats gets changed?
	for name, sub_config in pairs(self) do
		if name:sub(1, 1) ~= '_' and type(sub_config) == 'table' and name ~= 'super' then sub_config(enable) end
	end
end

function M:__tostring()
	---@type {[string]:any}
	local dump = {}
	for field, stack in pairs(vars[self.super]) do
		local override = stack[self]
		if override then dump[field] = override.new end
	end
	-- same traversal as __call: the nested sub-configs, not the internal state
	for name, sub_config in pairs(self) do
		if name:sub(1, 1) ~= '_' and type(sub_config) == 'table' and name ~= 'super' then dump[name] = sub_config end
	end
	return U.tbl_to_str(dump)
end

return M
