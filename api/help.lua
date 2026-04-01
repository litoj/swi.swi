local M = { _overrides = {} }
local o = M._overrides

o.enabled={}
function o.enabled.set(x)
	-- TODO: cache
end

---Enter or exit a custom mode that lists all bindings and other functions
rawset(swi, 'help', require 'swi.api.proxy'('swi.help', {}, M))
---@type swi.help
return swi.help
