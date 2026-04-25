---@module 'swi.lib.keybind_processor'
local U = require 'swi.lib.utils'

local M = {}

---@class swi.lib.keybind_processor: keybind_processor
---@field _mappings mode_mappings
---Function to set a mapping directly without updating the active mappings.
---Nil action gets replaced with the default handler for unbound keys
---@field rawmap fun(self:swi.lib.keybind_processor,b:string,action:fun()?,bindcfg:bindcfg?)
---@field warn_on_duplicates appmode_t|false

---@param self swi.lib.keybind_processor
---@return swi.lib.keybind_processor
function M.new(self)
	self._mappings = {}

	self.remap = function(b, bindcfg)
		b = U.transform_key(b)
		local old = self._mappings[b]
		bindcfg.trace = bindcfg.trace or debug.traceback()
		self._mappings[b] = bindcfg
		self:rawmap(b, type(bindcfg.cb) == 'string' and function() swi.exec(bindcfg.cb) end or bindcfg.cb, bindcfg)
		return old
	end

	self.unmap = function(b)
		b = U.transform_key(b)
		self._mappings[b] = nil
		self:rawmap(b)
	end

	local function pretty_trace(trace) return U.pretty_trace('keybind_processor.+map', trace) end

	self.map = function(bind, action, desc)
		local bindcfg = { ---@type bindcfg
			cb = action,
			desc = desc,
			trace = debug.traceback(),
		}

		for _, b in ipairs(U.tabled(bind)) do
			local old = self.remap(b, bindcfg)
			if self.warn_on_duplicates and old and not old.default then
				print(
					('Duplicate mapping: %s.map("%s", %s)'):format(
						self.warn_on_duplicates,
						b,
						pretty_trace(old.trace):match '^[^\n]+'
					)
				)
			end
		end
	end

	self.get_mappings = function()
		for _, v in pairs(self._mappings) do
			if not v._traced then
				v.trace = pretty_trace(v.trace)
				---@diagnostic disable-next-line: inject-field
				v._traced = true
			end
		end
		return self._mappings
	end

	return self
end

return M
