local e = require 'swi.api.eventloop'

---@class swi.api.proxy: proxy,metatable
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
	if type(fn) == 'table' and fn.set then
		fn.set(self, val, idx)
	else
		fn = self._api[(type(val) == 'boolean' and 'enable_' or 'set_') .. idx]
		if not fn then error('tried to assign: ' .. self._path .. '.' .. idx) end

		fn(val)
	end

	rawset(self, '_' .. idx, val) -- set in case a getter isn't available
	e.trigger { event = 'OptionSet', match = ('%s.%s'):format(self._path, idx), data = val }
end

---Create a dynamic table where variable I/O can be custom-defined
---Practically a metatable designed for automatic passthrough to a different api.
---@generic O: proxy
---@param base `O`
---@return O
function M.new(base) return setmetatable(base, M) end

return M
