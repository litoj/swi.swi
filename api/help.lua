local e = swi.eventloop

local M = { _api = {}, _path = 'swi.help', _overrides = {} }
local o = M._overrides

-- TODO: define list of custom mappings and actions that will get loaded on help activation
-- sub-modes to switch between will be: listing all variables, keybinds, autocommands/eventloop subs
-- and for keybinds also update the overlay when user switches modes
-- by default a 4th sub-mode will be selected that will list all help keybinds

o.enabled = {}
function o.enabled.set(x)
	-- TODO: cache current mappings and textlayer, inject custom keybinds and default help layer
	-- (keybinds in help overlay should be in the topright)
	--
	-- do the reverse when disabling

	-- after caching also the scale, set the scale to make the image appear as 1px to allow basically
	-- an empty screen
	-- TODO: do the same in gallery mode
	v.scale = 2 / v.get_image().width
end

--- TODO: in the future: add ways to select a variable and list help and its possible values

---Enter or exit a custom mode that lists all bindings and other functions
rawset(swi, 'help', require('swi.api.proxy').new(M))
---@type swi.help
return swi.help
