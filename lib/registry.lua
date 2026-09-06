---@module 'sai.lib.registry'

---One layer's override of a field or a bind
---@class sai.lib.registry.record
---@field layer? table the record's owner, set when the record takes its stack over
---@field new any value the override wants to set
---@field old any? value captured when the override took the field over; nil while the record is only parked (its layer cannot apply it yet)

---The per-(api, key) override stack. The array part holds the applied
---records in takeover order (the last one owns the value); the hash part
---parks the records of layers that cannot apply them yet, keyed by their
---layer. `stack[layer]` finds the layer's record in either place.
---@class sai.lib.registry.stack
---@field [integer] sai.lib.registry.record
---@field [table] sai.lib.registry.record
---@field set fun(self:sai.lib.registry.stack, layer:table, record?:sai.lib.registry.record):any put the layer's record on top, or remove it when the record is nil

local methods = {}

---Take the stack over with the layer's `record`, or remove the record when
---it is nil. The restore target always flows upward: from below the top it
---goes to the record above (ours keeps the supplied `old`, the on-screen
---value), on top it is kept on a write and returned on a removal for the
---caller to write back.
---@param self sai.lib.registry.stack
---@param layer table
---@param record? sai.lib.registry.record
---@return any the restore value when a record was removed on top
function methods:set(layer, record)
	local i
	for j = 1, #self do
		if self[j].layer == layer then
			i = j
			break
		end
	end
	local old = i and self[i].old
	local top = i == #self

	if i then
		if not top then self[i + 1].old = old end
		table.remove(self, i)
	end

	if record then
		record.layer = layer
		if top then record.old = old end
		rawset(self, layer, nil) -- else a later removal would expose the stale parked record again
		self[#self + 1] = record
	elseif top then
		return old
	else
		rawset(self, layer, nil) -- a parked record never applied: only its slot goes
	end
end

local stack_meta = {
	-- parked records die with their layer; the applied ones are removed by
	-- the layer's own disable
	__mode = 'k',
	__index = function(self, key)
		local m = methods[key]
		if m then return m end
		for i = 1, #self do
			if self[i].layer == key then return self[i] end
		end
	end,
}

local function new()
	-- every level springs into existence on demand: the modes write to the
	-- registry without any creation plumbing
	return setmetatable({}, {
		__mode = 'k',
		__index = function(reg, api)
			local stacks = setmetatable({}, {
				__index = function(stacks, key)
					local stack = setmetatable({}, stack_meta)
					rawset(stacks, key, stack)
					return stack
				end,
			})
			rawset(reg, api, stacks)
			return stacks
		end,
	})
end

---The shared override registries: `vars` for the reconfigurer's fields, `binds` for the remapper's binds
return { vars = new(), binds = new() }
