---@module 'swi.api.mode_text'

local U = require 'swi.lib.utils'
local proxy = require 'swi.lib.proxy'
local e = require 'swi.api.eventloop'

---@class swi.api.mode_text
---@field _api swayimg_appmode|swayimg.gallery
---@field _api_name appmode_t

local M = {}

---@class mode_text.tracker
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

local function replace_swi_vars(line, vars, ev)
	if ev then
		line = line:gsub(('{%s}'):format(ev.match), U.to_pretty_str(ev.data))
		if not line or #vars == 1 then return line end
	end

	-- process all other variables
	for var, path in line:gmatch '({swi%.([a-z0-9._]+)})' do
		local val = swi
		for key in path:gmatch '[^.]+' do
			val = val[key]
			if type(val) == 'function' then val = val() end
			if val == nil then return end
		end
		line = line:gsub(var, U.to_pretty_str(val))
	end
	return line
end

local function generate_exif_updater(line)
	return function(img) return replace_exif_vars(line, img) or '' end
end

local function generate_var_updater(line, varpaths)
	return { -- TODO: possible optimization by rendering only when mode and text are active + on modechange
		event = 'OptionSet',
		pattern = varpaths,
		callback = function(ev) return replace_swi_vars(line, varpaths, ev):gsub('{', '{{') or '' end,
	}
end

local function render_hook(processed, i, hook, ...)
	local out = hook(...)
	if type(out) == 'table' then
		i = i - 1
		for j, line in pairs(out) do
			processed[i + j] = line
		end
	elseif out then
		processed[i] = out
	end
end

---@param tracker mode_text.tracker
---@param img swayimg.image|swayimg.entry
local function render_on_img(tracker, api, placement, img)
	local p = tracker.processed
	for i, line in pairs(tracker) do
		if i ~= 'processed' then render_hook(p, i, line, img) end
	end
	api.set_text(placement, p)
end

local primed
---@param self swi.api.mode_text
local function initialize(self)
	local tracked = {}
	rawset(self, 'tracked', tracked)

	local function on_change(ev)
		if not next(tracked) then return end
		for placement, config in pairs(tracked) do
			render_on_img(config, self._api, placement, ev.data)
		end
	end

	if not swi.initialized then -- ensure we don't try to render before app has initialized
		if not primed then
			primed = render_on_img
			render_on_img = function() end
		end

		e.subscribe {
			event = 'SwiEnter',
			callback = function()
				render_on_img = primed
				on_change { data = U.lazy(self._api.get_image) }
				return true
			end,
		}
	end

	e.subscribe { event = 'ImgChange', mode = self._api_name, callback = on_change }
	return tracked
end

---@param self swi.api.mode_text
---@param placement block_position_t
local function set_text(self, x, placement)
	local group = ('%s.dyntext.%s'):format(self._api_name, placement)

	local tracked = rawget(self, 'tracked') ---@type {[block_position_t]:mode_text.tracker}
	if tracked and tracked[placement] then e.unsubscribe { group = group } end

	local new_tr = {}
	local processed = {}
	local has_hooks = false
	for i, v in pairs(x) do -- find all custom templates
		-- check for a custom template implementation and replace it with the correct generator
		if type(v) == 'string' then
			local varpaths = {}
			for path in v:gmatch '{(swi%.[a-z0-9._]+)}' do
				varpaths[#varpaths + 1] = path
			end

			if #varpaths > 0 then
				v = generate_var_updater(v, varpaths)
			elseif v:find '[^{]{[A-Z]' or v:find '^{[A-Z]' then
				v = generate_exif_updater(v)
			end
		end

		-- register the generators and normal lines to be ready to render and update
		if type(v) == 'table' then ---@cast v mode_base.text.dyntext
			has_hooks = true

			local cfg = U.soft_copy(v)
			cfg.callback = function(...)
				render_hook(processed, i, v.callback, ...)
				self._api.set_text(placement, processed)
			end
			cfg.group = group
			cfg.mode = self._api_name
			e.subscribe(cfg)

			-- load the default value
			render_hook(processed, i, v.callback, nil)
		elseif type(v) == 'function' then
			new_tr[i] = v
		else
			processed[i] = v
		end
	end

	if next(new_tr) or has_hooks then
		if not tracked then tracked = initialize(self) end

		new_tr.processed = processed
		tracked[placement] = new_tr
		if swayimg.get_mode() == self._api_name then
			render_on_img(new_tr, self._api, placement, U.lazy(self._api.get_image))
		end
	else
		if tracked then tracked[placement] = nil end
		self._api.set_text(placement, x)
	end
end

---@param self swi.api.mode_text
---@return swi.api.mode_text
function M.new(self)
	---@diagnostic disable: inject-field
	self._path = ('swi.%s.text'):format(self._api_name)
	self._overrides = { ['*'] = { set = set_text } }
	return proxy.new(self)
end

return M
