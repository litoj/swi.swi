---@module 'swi.api.proxy'

local e = require 'swi.api.eventloop'

---@class swi.api.proxy: proxy
local M = {}

function M.__index(self, idx)
	local v = self._overrides[idx] or self._overrides['*']
	if v and v.get then return v.get(self, idx) end

	v = self._api[idx] -- get fn
	if v ~= nil then -- directly forward access to the old api
		if type(v) == 'function' then rawset(self, idx, v) end
		return v
	end

	v = self._api['get_' .. idx] -- get variable
	if v then return v() end -- idiomatic getter

	v = rawget(self, '_' .. idx)
	if v ~= nil then return v end -- read local copy of the last set value

	error('tried to get: ' .. self._path .. '.' .. idx)
end

function M.__newindex(self, idx, val)
	local fn = self._overrides[idx] or self._overrides['*']
	local old = rawget(self, '_' .. idx)
	if type(fn) == 'table' and fn.set then
		-- set the field only if the setter allows it
		---@diagnostic disable-next-line: cast-local-type
		fn = fn.set(self, val, idx)
		if fn == nil then
			rawset(self, '_' .. idx, val)
			---@diagnostic disable-next-line: cast-local-type
			fn = true
		end
	else
		fn = type(val) == 'boolean' and self._api['enable_' .. idx] or self._api['set_' .. idx]
		if not fn then error('tried to assign: ' .. self._path .. '.' .. idx) end

		fn(val)
		rawset(self, '_' .. idx, val) -- set in case a getter isn't available
	end

	if fn and self._trigger then
		e.trigger { event = 'OptionSet', match = ('%s.%s'):format(self._path, idx), data = val, old_data = old }
	end
end

---Create a dynamic table where variable I/O can be custom-defined
---Practically a metatable designed for automatic passthrough to a different api.
---@generic O: proxy
---@param base `O`
---@return O
function M.new(base)
	---@diagnostic disable-next-line: inject-field
	if not base._api then base._api = {} end
	if base._trigger == nil then base._trigger = true end
	return setmetatable(base, M)
end

return M
