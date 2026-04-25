---@diagnostic disable: invisible
---@module 'swi.api.mode_base'

local proxy = require 'swi.lib.proxy'
local e = require 'swi.api.eventloop'
local mode_text = require 'swi.api.mode_text'
local kp = require 'swi.lib.keybind_processor'

---@class swi.api.mode_base: mode_base, swi.lib.keybind_processor
---@field _api swayimg_appmode
local M = { warn_on_duplicates = true }

---@param self swi.api.mode_base
---@param api_name appmode_t
function M.new(self, api_name)
	local api = self._api
	self._path = 'swi.' .. api_name
	for _, sig in ipairs { 'USR1', 'USR2' } do
		api.on_signal(sig, function() e.trigger { event = 'Signal', match = sig } end)
	end

	self.text = mode_text.new(api, api_name)

	---@diagnostic disable-next-line: inject-field
	self._mark_color = 0xff808080
	---@diagnostic disable-next-line: inject-field
	self._pinch_factor = 1.0

	function self:rawmap(b, action)
		if b:match 'Mouse' or b:match 'Scroll' then
			self._api.on_mouse(b, action or function() swi.text.status = 'Unhandled mouse: ' .. b end)
		else
			self._api.on_key(b, action or function() swi.text.status = 'Unhandled key: ' .. b end)
		end
	end
	---@diagnostic disable-next-line: assign-type-mismatch
	self.warn_on_duplicates = M.warn_on_duplicates and api_name
	kp.new(self)

	return proxy.new(self)
end

return M
