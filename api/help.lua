local M = {
	enabled = {
		set = function() end,
		get = function() end,
	},
}

---Enter or exit a custom mode that lists all bindings and other functions
rawset(swi, 'help', require 'swi.api.proxy'('swi.help', {}, M))
---@type swi.help
return swi.help
