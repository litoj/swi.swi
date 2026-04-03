---@diagnostic disable: invisible
---@module 'swi.api.mode_base'

local U = require 'swi.utils'
local proxy = require 'swi.api.proxy'
local e = require 'swi.api.eventloop'
local mode_text = require 'swi.api.mode_text'

---@class swi.api.mode_base: mode_base
---@field _api swayimg_appmode
---@field _mappings table<string,mapping>
---Function to set a mapping directly without updating the active mappings.
---Nil gets replaced with the default handler for unbound keys
---@field _set_raw_mapping fun(b:string,action:fun()?)
local M = { warn_on_duplicates = false }

---@param self swi.api.mode_base
---@param api_name appmode_t
function M.new(self, api_name)
	local api = self._api
	self._path = 'swi.' .. api_name
	for _, sig in ipairs { 'USR1', 'USR2' } do
		api.on_signal(sig, function() e.trigger { event = 'Signal', match = sig } end)
	end

	self._set_raw_mapping = function(b, action)
		if b:match 'Mouse' or b:match 'Scroll' then
			api.on_mouse(b, action or function() swi.text.status = 'Unhandled mouse: ' .. b end)
		else
			api.on_key(b, action or function() swi.text.status = 'Unhandled key: ' .. b end)
		end
	end
	self._mappings = {}

	self.text = mode_text.new(api, api_name)
	self.map = function(b, action, desc)
		local mapcfg = { ---@type mapping
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

			if M.warn_on_duplicates and self._mappings[b] then
				print(('Duplicate mapping: %s.map("%s")'):format(api_name, b))
			end
			self._mappings[b] = mapcfg
			self._set_raw_mapping(b, action)
		end
	end
	self.get_mappings = function()
		for _, v in pairs(self._mappings) do
			if not v._traced then
				v.trace = U.pretty_trace('mode_base.+map', v.trace)
				---@diagnostic disable-next-line: inject-field
				v._traced = true
			end
		end
		return self._mappings
	end
	self.unmap = function(b)
		b = U.transform_key(b)
		self._mappings[b] = nil
		self._set_raw_mapping(b)
	end

	---@diagnostic disable-next-line: inject-field
	self._mark_color = 0xff808080
	---@diagnostic disable-next-line: inject-field
	self._pinch_factor = 1.0

	return proxy.new(self)
end

return M
