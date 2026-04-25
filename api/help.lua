---@diagnostic disable: invisible
---@module 'swi.api.help'

local pager = require 'swi.lib.pager'
local e = swi.eventloop
local U = require 'swi.lib.utils'

---@class swi.api.help: swi.help
---@field pager swi.lib.pager
---@field help_pager swi.lib.pager
---@field keybinder swi.lib.bind_override
local M = {
	_api = {},
	_path = 'swi.help',
	_overrides = {},
	_cache = {},
	_tab = 1,
	_enabled = false,
	key_alignment = 15,
}

local modes = { 'gallery', 'viewer', 'slideshow' }

---@class KeymapItem: bindcfg
---@field bind string the keycombo under which the callback is registered

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
			if
				(raw_api and (raw_api[setter_name] or raw_api[enabler_name]))
				or (overrides and overrides[field_name])
			then
				fields[#fields + 1] = { name = field_name, value = value }
			end
		end
	end

	return fields
end

---Gather all key mappings in the application by mode
---@param mode_names appmode_t|appmode_t[]?
---@return table<appmode_t,KeymapItem[]> sections Map of mode names to their key bindings
local function gather_keymaps(mode_names)
	local result = {}
	for _, name in ipairs(U.tabled(mode_names) or modes) do
		local items = {}
		for k, v in pairs(swi[name].get_mappings()) do
			v = U.soft_copy(v)
			v.bind = k
			items[#items + 1] = v
		end
		table.sort(items, function(a, b)
			if not a.desc ~= not b.desc then return not b.desc end
			if not a.desc and type(a.cb) ~= type(b.cb) then return type(a.cb) == 'string' end
			return #a.trace < #b.trace or (#a.trace == #b.trace and a.trace < b.trace)
		end)
		result[name] = items
	end
	return result
end

---Gather all settings/configuration variables
---@return {name:string,list:{name:string,value:string}} sections List of all setting sections with their variables
local function gather_settings()
	-- Dynamically find settings based on setter methods and overrides
	local targets = {
		swi,
		swi.text,
		swi.imagelist,
		swi.gallery,
		swi.viewer,
		swi.slideshow,
	}
	local result = {}
	for _, swiapi in ipairs(targets) do
		local list = {}

		local settable_fields = discover_settable_fields(swiapi)

		for _, field in ipairs(settable_fields) do
			list[#list + 1] = { name = field.name, value = U.to_pretty_str(field.value):gsub('{', '{{') }
		end

		if #list > 0 then result[#result + 1] = { name = swiapi._path, list = list } end
	end
	return result
end

-- Overlay tabs definition: each with a name and provider function
local function mode_bindlist(mode)
	mode = mode or swi.mode
	local function get_desc(item) return item.desc or (type(item.cb) == 'string' and item.cb) or item.trace end

	local fmt = ('  %%%ds: %%s'):format(M.key_alignment)
	local out = {}
	local binds = gather_keymaps(mode)[mode]
	if #binds > 0 then
		local i = 1
		local item = binds[i]
		local last = { item.trace, { U.short_key_name(item.bind) }, get_desc(item) }
		while i < #binds do -- group bindings by what they bind to
			i = i + 1
			item = binds[i]
			if last[1] ~= item.trace then
				out[#out + 1] = (fmt):format(table.concat(last[2], ', '), last[3]:gsub('\t', ''):gsub('\n', ' '))

				last = { item.trace, {}, get_desc(item) }
			end
			last[2][#last[2] + 1] = item.bind --U.short_key_name(item.bind)
		end

		out[#out + 1] = ('  %20s %s'):format(table.concat(last[2], ', '), last[3]:gsub('[\t\n]', ' '))
	end

	return ('%s%s Binds'):format(mode:sub(1, 1):upper(), mode:sub(2)), out
end

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

local function settings_list()
	local out = {}
	-- First pass: collect lines + track selected index mapping
	for i, sec in ipairs(gather_settings()) do
		out[#out + 1] = ('%s:'):format(sec.name:upper())
		for j, v in ipairs(sec.list) do
			out[#out + 1] = ('  %s\t{%s.%s}'):format(v.name, sec.name, v.name)
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

-- Overlay navigation and exit bindings (add scroll)
local overlay_keybinds = {
	{
		binds = { 'Right', 'Tab' },
		cb = function() swi.help.tab = swi.help.tab + 1 end,
		desc = 'Next help tab',
	},
	{
		binds = { 'Left', 'Shift+Tab' },
		cb = function() swi.help.tab = swi.help.tab - 1 end,
		desc = 'Previous help tab',
	},
	{
		binds = { 'Up', '<UMS>' },
		cb = function() swi.help.pager.line = swi.help.pager.line - 1 end,
		desc = 'Scroll up',
	},
	{
		binds = { 'Down', '<DMS>' },
		cb = function() swi.help.pager.line = swi.help.pager.line + 1 end,
		desc = 'Scroll down',
	},
	{
		binds = { 'PageUp' },
		cb = function() swi.help.pager.line = swi.help.pager.line - swi.help.pager.page_size end,
		desc = 'Page up',
	},
	{
		binds = { 'PageDown' },
		cb = function() swi.help.pager.line = swi.help.pager.line + swi.help.pager.page_size end,
		desc = 'Page down',
	},
	{
		binds = { 'Escape', 'q' },
		cb = function() swi.help.enabled = false end,
		desc = 'Exit help overlay',
	},
}

function M.activate(self)
	if not rawget(M, 'pager') then
		rawset(M, 'pager', pager.new())
		rawset(M, 'help_pager', pager.new())
		M.help_pager.position = 'topright'
		M.help_pager.lines = (function()
			local lines = {}
			for _, k in ipairs(overlay_keybinds) do
				lines[#lines + 1] = ('%s\t%s'):format(table.concat(k.binds, ', '), k.desc)
			end
			return lines
		end)()

		-- Create the keybind overlay and register all help bindings
		rawset(M, 'keybinder', require('swi.lib.bind_override').new())
		for _, map in ipairs(overlay_keybinds) do
			M.keybinder.map(map.binds, map.cb, map.desc)
		end
	end
	local mode = swi.mode
	self.pager.mode = mode
	self.help_pager.mode = mode
	self.keybinder.mode = mode

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
			self.keybinder.mode = ev.mode
		end,
	}

	M.pager.enabled = true
	M.help_pager.enabled = true
	M.keybinder.enabled = true
end

function M.deactivate(self)
	M.pager.enabled = false
	M.help_pager.enabled = false

	local ovars = self._cache.vars
	if swi.mode ~= 'viewer' then ovars['swi.viewer.scale'] = nil end
	if swi.mode ~= 'slideshow' then ovars['swi.slideshow.scale'] = nil end
	U.restore_captured_changes(ovars)
	if swi.mode ~= 'gallery' then swi[swi.mode].scale = swi[swi.mode].default_scale end

	e.unsubscribe { id = self._cache.mode_hook }

	M.keybinder.enabled = false
end

M._overrides.enabled = {
	---@param self swi.api.help
	set = function(self, val)
		if val == self._enabled then return end
		if val then
			self:activate()
		else
			self:deactivate()
		end
		self._enabled = val
	end,
}

--- TODO: in the future: add ways to select a variable and list help and its possible values

---Enter or exit a custom mode that lists all bindings and other functions
rawset(swi, 'help', require('swi.lib.proxy').new(M))
---@type swi.help
return swi.help
