---Create a dynamic table where variable I/O can be custom-defined
---Practically a metatable designed for automatic passthrough to a different api.
---@generic O
---@param name string
---@param api table
---@param overrides `O` also can be used as a base if `_overrides` is defined
---@return O
return function(name, api, overrides)
	overrides = overrides or {}

	---@type proxy
	local base
	if overrides._overrides then
		base = overrides
		overrides = base._overrides
	else
		base = { _overrides = overrides }
	end
	local overrider_fields = { get = 'function', set = 'function' }
	for k, o in pairs(overrides) do
		local is_override = type(o) == 'table' and getmetatable(o) == nil
		if is_override then
			for i, v in pairs(o) do
				if type(v) ~= overrider_fields[i] then
					is_override = false
					break
				end
			end
		end

		if not is_override then
			base[k] = o
			overrides[k] = nil
		end
	end

	return setmetatable(base, {
		__index = function(self, idx)
			local v = overrides[idx] or overrides['*']
			if v and v.get then return v.get(self, idx) end

			v = api[idx] -- get fn
			if v ~= nil then -- directly forward access to the old api
				if type(v) == 'function' then rawset(self, idx, v) end
				return v
			end

			v = api['get_' .. idx] -- get variable
			if v then return v() end -- idiomatic getter

			v = rawget(self, '_' .. idx)
			if v ~= nil then return v end -- read local copy of the last set value

			error('tried to get: ' .. name .. '.' .. idx)
		end,

		__newindex = function(self, idx, val)
			local fn = overrides[idx] or overrides['*']
			if type(fn) == 'table' and fn.set then
				fn.set(val, self, idx)
			else
				fn = api[(type(val) == 'boolean' and 'enable_' or 'set_') .. idx]
				if not fn then error('tried to assign: ' .. name .. '.' .. idx) end

				fn(val)
			end

			rawset(self, '_' .. idx, val) -- set in case a getter isn't available
			swi.eventloop.trigger { event = 'OptionSet', match = ('%s.%s'):format(name, idx), data = val }
		end,
	})
end
