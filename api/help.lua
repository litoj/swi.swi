---@diagnostic disable: invisible
---@module 'swi.api.help'

local e = swi.eventloop
local proxy = require 'swi.lib.proxy'
local pager = require 'swi.lib.pager'
local U = require 'swi.lib.utils'

---@class swi.api.help: swi.help
local M = {
	_path = 'swi.help',
	_api = {},
	_overrides = {},
	_cache = {},

	_tab = 1,
	_enabled = false,

	bind_fmt = '%20s: %s',
}

---@diagnostic disable-next-line: missing-fields
M.pager = pager.new {
	_path = 'swi.help.pager',
	_trigger = true,
	position = 'topleft',
}

---@diagnostic disable-next-line: missing-fields
M.help_pager = pager.new {
	title = 'Help binds:\t',
	position = 'topright',
}

-- To defer user mapping override handling
M.bind_override = require('swi.lib.bind_override').new {
	_path = 'swi.help',
}

local modes = { 'gallery', 'viewer', 'slideshow' }

---@return string title
---@return string[] lines
local function mode_bindlist(mode, fmt_str)
	mode = mode or swi.mode

	local binds = {}
	for k, v in pairs(swi[mode].get_mappings()) do ---@cast v bindcfg
		if not binds[v.cb] then
			binds[v.cb] = {
				bind = {},
				info = v.desc or (type(v.cb) == 'string' and v.cb) or v.trace,
				-- quality of the source information
				qual = v.default and 0 or (v.desc and 1) or (type(v.cb) == 'string' and 2) or 3,
			}
		end
		table.insert(binds[v.cb].bind, k)
	end

	local out = {}
	for _, v in pairs(binds) do
		out[#out + 1] = v
	end
	binds = out
	table.sort(binds, function(a, b)
		if a.qual ~= b.qual then return a.qual < b.qual end
		if a.qual < 3 then return a.info < b.info end
		return #a.info < #b.info or (#a.info == #b.info and a.info < b.info)
	end)

	if not fmt_str then fmt_str = M.bind_fmt end
	out = {}
	for _, k in ipairs(binds) do
		table.sort(k.bind, function(a, b) return #a < #b or (#a == #b and a < b) end)
		out[#out + 1] = (fmt_str):format(table.concat(k.bind, ', '), k.info:gsub('[\t\n]', ' '))
	end

	return ('%s%s Binds'):format(mode:sub(1, 1):upper(), mode:sub(2)), out
end

---@return string title
---@return string[] lines
local function complete_bindlist()
	local mode_order = { swi.mode }
	for _, m in ipairs(modes) do
		if mode_order[1] ~= m then mode_order[#mode_order + 1] = m end
	end

	local out = {}
	for _, m in ipairs(mode_order) do
		local name, lines = mode_bindlist(m)
		out[#out + 1] = ('%s: %d bindings'):format(name, #lines)
		for _, line in ipairs(lines) do
			out[#out + 1] = '  ' .. line
		end
	end

	return 'All Binds', out
end

---@param target proxy API object to inspect
---@return table<string,any>[] fields List of settable fields with their current values
local function discover_settable_fields(target)
	local raw_api = target._api
	local overrides = target._overrides
	local fields = {}

	for field, value in pairs(target) do
		if field:sub(1, 1) == '_' then
			local field_name = field:sub(2)
			local setter_name = 'set_' .. field_name
			local enabler_name = 'enable_' .. field_name

			-- Check if backing field has an official setter, enabler, or override
			if overrides[field_name] or raw_api[setter_name] or raw_api[enabler_name] then
				fields[#fields + 1] = { name = field_name, value = value }
			end
		end
	end

	return fields
end

---@return string title
---@return string[]
local function settings_list()
	local out = {}
	for _, swiapi in ipairs {
		swi,
		swi.text,
		swi.imagelist,
		swi.gallery,
		swi.viewer,
		swi.slideshow,
	} do
		out[#out + 1] = ('%s:'):format(swiapi._path:upper())

		for _, field in ipairs(discover_settable_fields(swiapi)) do
			out[#out + 1] = ('  %s\t{%s.%s}'):format(field.name, swiapi._path, field.name)
		end
	end

	return 'Settings', out
end

local tab_generators = { mode_bindlist, settings_list, complete_bindlist }

M._overrides.tab = {
	---@param self swi.api.help
	set = function(self, idx)
		self._tab = (idx - 1) % #tab_generators + 1
		M.pager:bulk_change(function(pager)
			local name, lines = tab_generators[self._tab]()
			pager.title = ('[Help %d/%d]: %s\t'):format(self._tab, #tab_generators, name)
			pager.lines = lines
			pager.line = 1
		end)
		return true
	end,
}

function M.activate(self)
	local mode = swi.mode
	self.pager.mode = mode
	self.help_pager.mode = mode
	self.bind_override.mode = mode

	---@diagnostic disable-next-line: param-type-mismatch
	_, self.help_pager.lines = mode_bindlist('help', '%s\t%s')
	self.tab = 1

	do
		local captured = U.capture_opt_changes()
		swi.viewer.default_scale = 'keep_by_width'
		swi.slideshow.default_scale = 'keep_by_width'
		if mode ~= 'gallery' then
			--- 100px
			swi[mode].scale = 100 / swi[mode].get_image().width
		end
		local gspace = swi.gallery.thumb_size + swi.gallery.padding_size
		swi.gallery.thumb_size = gspace / 3
		swi.gallery.padding_size = gspace / 3
		swi.text.enabled = true
		self._cache.vars = captured()
	end

	-- NOTE: always ensure keybinder is updated last to load mode keybinds first
	self._cache.mode_hook = e.subscribe {
		event = 'ModeChanged',
		mode = modes,
		callback = function(ev)
			self.pager:bulk_change(function(p)
				p.mode = ev.mode
				self.tab = self.tab -- regenerate content in case we're on keybindings
			end)
			self.help_pager.mode = ev.mode
			self.bind_override.mode = ev.mode
		end,
	}

	M.pager.enabled = true
	M.help_pager.enabled = true
	M.bind_override.enabled = true
end

function M.deactivate(self)
	M.pager.enabled = false
	M.help_pager.enabled = false
	M.bind_override.enabled = false

	local ovars = self._cache.vars
	if swi.mode ~= 'viewer' then ovars['swi.viewer.scale'] = nil end
	if swi.mode ~= 'slideshow' then ovars['swi.slideshow.scale'] = nil end
	U.restore_captured_changes(ovars)
	if swi.mode ~= 'gallery' then swi[swi.mode].scale = swi[swi.mode].default_scale end

	e.unsubscribe { id = self._cache.mode_hook }
end

M._overrides.enabled = {
	---@param self swi.api.help
	set = function(self, val)
		if val == self._enabled then return true end
		if val then
			self:activate()
		else
			self:deactivate()
		end
	end,
}

--- TODO: in the future: add ways to select a variable and list help and its possible values

for k, v in pairs(M.bind_override) do
	if M[k] == nil then M[k] = v end
end

rawset(swi, 'help', proxy.new(M))

---@type swi.help
return swi.help
