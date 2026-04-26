---@module 'swi.lib.bind_override'
---@diagnostic disable: invisible

local proxy = require 'swi.lib.proxy'
local U = require 'swi.lib.utils'
local kp = require 'swi.lib.keybind_processor'

---@class swi.lib.bind_override.base: proxy
---@field mode? appmode_t in which mode should we set the bindings
---@field enabled? boolean

---Keybind override: temporarily replace keybindings in current mode.
---Implements the same map/unmap interface as mode_base.
---@class swi.lib.bind_override: swi.lib.keybind_processor, swi.lib.bind_override.base
local M = {
	_path = 'bind_override',
	_overrides = {},
	_trigger = false,
	warn_on_duplicates = true, --- for keybind_processor

	---@type swi.api.mode_base
	---@diagnostic disable-next-line: assign-type-mismatch
	_mode_api = false, ---@private
	_enabled = false, ---@private
	_omaps = {}, ---@type bind_map saved original mappings per mode
}

local function rawmap(api, b, cfg)
	if cfg then
		api.remap(b, cfg)
	else
		api.unmap(b)
	end
end

-- for keybind_processor
function M:_rawmap(b, _, cfg)
	if self._enabled then
		self._omaps[b] = self._mode_api._mappings[b]
		rawmap(self._mode_api, b, cfg)
	end
end

M._overrides.mode = {
	---@param self swi.lib.bind_override
	set = function(self, mode)
		if self.mode == mode then return false end

		local oe = self._enabled
		self.enabled = false
		---@diagnostic disable-next-line: assign-type-mismatch
		self._mode_api = swi[mode]
		self.enabled = oe
		return false
	end,
	get = function(self)
		return ({
			[swi.viewer] = 'viewer',
			[swi.slideshow] = 'slideshow',
			[swi.gallery] = 'gallery',
		})[self._mode_api]
	end,
}

M._overrides.enabled = {
	---@param self swi.lib.bind_override
	set = function(self, val)
		if val == self._enabled then return end
		if not self._mode_api then self.mode = swi.mode end
		self._enabled = val

		local api = self._mode_api
		if val then
			local cur = api._mappings
			for b, cfg in pairs(self._mappings) do
				self._omaps[b] = cur[b]
				rawmap(api, b, cfg)
			end
		else
			for b, cfg in pairs(self._omaps) do
				rawmap(api, b, cfg)
			end
			self._omaps = {}
		end
		return false
	end,
}

---@class bindcfg_contained: bindcfg
---@field bind string|string[]
---@field trace nil forbidden - bulkmap will set the stacktrace instead
---@field default nil forbidden - determined by bulk setting

---@alias mappinglist {[integer]:bindcfg_contained}

---@param maplist mappinglist
---@param as_default boolean?
function M:bulkmap(maplist, as_default)
	local deftrace = U.pretty_trace('bind_override.+new', debug.traceback())
	local maps = self._mappings
	for k, v in pairs(maplist) do
		local cfg = { cb = v.cb, desc = v.desc, default = as_default, trace = deftrace, _traced = true }
		for _, b in ipairs(U.tabled(v.bind or k)) do
			maps[U.transform_key(b)] = cfg
		end
	end
end

---@class swi.lib.bind_override.cfg
---@field default_mappings? mappinglist

---@param opts? swi.lib.bind_override.cfg
---@return swi.lib.bind_override
function M.new(opts)
	local self = U.soft_copy(M)
	kp.new(self)

	self = proxy.new(self) ---@cast self swi.lib.bind_override
	if not opts then return self end

	if opts.default_mappings then
		self:bulkmap(opts.default_mappings, true)
		opts.default_mappings = nil
	end

	for k, v in pairs(opts) do
		self[k] = v
	end

	return self
end

return M
