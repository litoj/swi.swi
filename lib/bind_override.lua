---@module 'swi.lib.bind_override'
---@diagnostic disable: invisible

local proxy = require 'swi.lib.proxy'
local U = require 'swi.lib.utils'
local kp = require 'swi.lib.keybind_processor'

---Keybind override: temporarily replace keybindings in current mode.
---Implements the same map/unmap interface as mode_base.
---@class swi.lib.bind_override: proxy, swi.lib.keybind_processor
---@field mode appmode_t which mode to apply the bindings to
---@field enabled boolean activate or deactivate the override
local M = {
	_path = 'bind_override', ---@private
	_api = {}, ---@private
	_overrides = {}, ---@private
	_trigger = false, ---@private
	warn_on_duplicates = false, ---@private for keybind_processor

	---@diagnostic disable-next-line: missing-fields
	_mode_api = {}, ---@type swi.api.mode_base
	_enabled = false, ---@private
	_omaps = {}, ---@type mode_mappings saved original mappings per mode
}

function M:_rawmap(b, cfg)
	if cfg then
		self._mode_api.remap(b, cfg)
	else
		self._mode_api.unmap(b)
	end
end

function M:rawmap(b, _, cfg)
	if self._enabled then
		self._omaps[b] = self._mode_api._mappings[b]
		self:_rawmap(b, cfg)
	end
end

M._overrides.mode = {
	---@param self swi.lib.bind_override
	set = function(self, mode)
		local oe = self._enabled
		self.enabled = false
		---@diagnostic disable-next-line: assign-type-mismatch
		self._mode_api = swi[mode]
		self.enabled = oe
		return false
	end,
	get = function(self)
		return ({ [swi.viewer] = 'viewer', [swi.slideshow] = 'slideshow', [swi.gallery] = 'gallery' })[self._mode_api]
	end,
}

M._overrides.enabled = {
	---@param self swi.lib.bind_override
	set = function(self, val)
		if val == self._enabled then return end
		self._enabled = val

		if val then
			local cur = self._mode_api._mappings
			for b, cfg in pairs(self._mappings) do
				self._omaps[b] = cur[b]
				self:_rawmap(b, cfg)
			end
		else
			for b, cfg in pairs(self._omaps) do
				self:_rawmap(b, cfg)
			end
			self._omaps = {}
		end
		return false
	end,
}

---@return swi.lib.bind_override
function M.new()
	local self = U.soft_copy(M)
	kp.new(self)
	return proxy.new(self)
end

return M
