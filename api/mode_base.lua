---@diagnostic disable: invisible
local U = require 'swi.utils'
local proxy = require 'swi.api.proxy'
local e = require 'swi.api.eventloop'

---@class swi.api.mode_base: mode_base
---@field _api swayimg_appmode
local M = {}
---@class swi.api.mode_base.text: mode_base.text
---@field _api swayimg_appmode|swayimg.gallery
---@field _api_name appmode_t
local text = {}
M.text = text

---@class mode_base.text.tracker
---@field [integer] extended_text_template
---@field dynvar {[string]:integer}
---@field processed string[]

---@param img swayimg.image|swayimg.entry
local function replace_exif_vars(line, img)
	for var, path in line:gmatch '({([A-Z][A-Za-z0-9.]+)})' do
		path = U.format_exif(img.meta, path) -- format the value
		line = path and line:gsub(var, path)
	end
	return line
end

local function render_hook(processed, i, hook, ...)
	local out = hook(...)
	if not out then return end
	for line in out:gmatch '[^\n]+' do
		processed[i] = line
		i = i + 1
	end
end

---@param tracker mode_base.text.tracker
---@param img swayimg.image|swayimg.entry
function text.render_on_img(tracker, api, placement, img)
	local p = tracker.processed
	for i, line in pairs(tracker) do
		if type(i) == 'number' then
			if type(line) == 'function' then
				render_hook(p, i, line, img)
			else
				p[i] = replace_exif_vars(line, img)
			end
		end
	end
	api.set_text(placement, p)
end

local primed
function text.initialize(self)
	local tracked = {}
	rawset(self, 'tracked', tracked)

	local function on_change(ev)
		if not next(tracked) then return end
		for placement, config in pairs(tracked) do
			text.render_on_img(config, self._api, placement, ev.data)
		end
	end

	if not primed then -- ensure we don't try to render before app has initialized
		if not swi.initialized then
			primed = M.render_on_img
			M.render_on_img = function() end
			e.subscribe {
				event = 'SwiEnter',
				callback = function()
					M.render_on_img = primed
					on_change { data = U.lazy(self._api.get_image) }
				end,
			}
		else
			primed = true
		end
	end

	e.subscribe { event = 'ImgChange', mode = self._api_name, callback = on_change }
	return tracked
end

local function generate_var_updater(line, varpaths)
	local function single_var(ev) return line:gsub(('{%s}'):format(ev.match), U.to_pretty_str(ev.data)) end

	local function multi_var(ev)
		line = single_var(ev)
		-- process all other variables
		for var, path in line:gmatch '({swi%.([a-z0-9._]+)})' do
			local val = swi
			for key in path:gmatch '[^.]+' do
				val = val[key]
				if val == nil then return end
			end
			line = line:gsub(var, U.to_pretty_str(val))
		end
		return line
	end

	return {
		event = 'OptionSet',
		pattern = varpaths,
		callback = #varpaths == 1 and single_var or multi_var,
	}
end

---@param placement block_position_t
function text.set(self, x, placement)
	local group = ('%s.dyntext.%s'):format(self._api_name, placement)

	local tracked = rawget(self, 'tracked') ---@type {[block_position_t]:mode_base.text.tracker}
	if tracked and tracked[placement] then e.unsubscribe { group = group } end

	local new_tr = {}
	local processed = {}
	local has_hooks = false
	for i, v in pairs(x) do -- find all custom templates
		if type(v) == 'string' then
			local varpaths = {}
			for path in v:gmatch '{(swi%.[a-z0-9._]+)}' do
				varpaths[#varpaths + 1] = path
			end
			if #varpaths > 1 then v = generate_var_updater(v, varpaths) end
		end

		if type(v) == 'table' then
			has_hooks = true

			local hook = v.callback
			v.callback = function(...)
				render_hook(processed, i, hook, ...)
				self._api.set_text(placement, processed)
			end
			v.group = group
			e.subscribe(v)

			processed[i] = v.callback() -- load the default value
		elseif type(v) == 'function' or v:find '{[A-Z]' then
			new_tr[i] = v
		else
			processed[i] = v
		end
	end

	if next(new_tr) or has_hooks then
		if not tracked then tracked = text.initialize(self) end

		new_tr.processed = processed
		tracked[placement] = new_tr
		text.render_on_img(new_tr, self._api, placement, U.lazy(self._api.get_image))
	else
		if tracked then tracked[placement] = nil end
		self._api.set_text(placement, x)
	end
end

function text.get(self, idx) return rawget(self, '_' .. idx) end

---@param api swayimg_appmode|swayimg.gallery
---@param name appmode_t
---@return mode_base.text
function text.new(api, name)
	return proxy.new {
		_path = ('swi.%s.text'):format(name),
		_api_name = name,
		_api = api,
		_overrides = { ['*'] = { set = text.set, get = text.get } },
	}
end

local function dummy() end

---@param self mode_base
---@param api_name appmode_t
function M.new(self, api_name)
	local api = self._api
	self._path = 'swi.' .. api_name
	for _, sig in ipairs { 'USR1', 'USR2' } do
		self._api.on_signal(sig, function() e.trigger { event = 'Signal', match = sig } end)
	end

	local mappings = {}
	local function setmap(b, action)
		if b:match 'Mouse' or b:match 'Scroll' then
			api.on_mouse(b, action)
		else
			api.on_key(b, action)
		end
	end

	self.text = text.new(api, api_name)
	self.map = function(b, action, desc)
		local mapcfg = {
			cb = action,
			desc = desc,
			trace = debug.traceback(),
		}

		if type(action) == 'string' then
			local cmd = action
			action = function() swi.exec(cmd) end
		end

		---@diagnostic disable-next-line: redefined-local
		for _, b in ipairs(type(b) == 'table' and b or { b }) do
			b = U.transform_key(b)

			if mappings[b] then error(('%s.map("%s") already set'):format(api_name, b)) end
			mappings[b] = mapcfg
			setmap(b, action)
		end
	end
	self.get_mappings = function()
		for _, v in pairs(mappings) do
			if not v.traced then
				v.trace = U.pretty_trace('mode_base[^\n]-map', v.trace)
				v.traced = true
			end
		end
		return mappings
	end
	self.unmap = function(b)
		b = U.transform_key(b)
		mappings[b] = nil
		setmap(b, dummy)
	end

	return proxy.new(self)
end

return M
