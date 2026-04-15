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
local M = { warn_on_duplicates = true }

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

	local function pretty_trace(trace) return U.pretty_trace('mode_base.+map', trace) end

	self.remap = function(b, bindcfg)
		b = U.transform_key(b)
		bindcfg.trace = bindcfg.trace or debug.traceback()

		local old = self._mappings[b]
		self._mappings[b] = bindcfg
		self._set_raw_mapping(b, type(bindcfg.cb) == 'string' and function() swi.exec(bindcfg.cb) end or bindcfg.cb)
		return old
	end

	self.map = function(bind, action, desc)
		local bindcfg = { ---@type mapping
			cb = action,
			desc = desc,
			trace = debug.traceback(),
		}

		for _, b in ipairs(U.tabled(bind)) do
			local old = self.remap(b, bindcfg)
			if M.warn_on_duplicates and old and not old.default then
				print(
					('Duplicate mapping: %s.map("%s", %s)'):format(api_name, b, pretty_trace(old.trace):match '^[^\n]+')
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
