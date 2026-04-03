---@module 'swi.api.keymappings'
local M = {}

local g = swi.gallery
local v = swi.viewer
local s = swi.slideshow
local t = swi.text
local l = swi.imagelist

---@alias bindmode
---| 'v' # viewer mode
---| 's' # slideshow mode
---| 'g' # gallery mode
---| '' # slideshow and viewer modes
---| 'a' # all modes

local modemap = { [''] = { v, s }, a = { v, s, g }, g = { g }, v = { v }, s = { s } }

---@param mode bindmode
---@param binds string|string[]
---@param cb string|fun()
---@param desc string?
function M.map(mode, binds, cb, desc)
	for _, m in ipairs(modemap[mode]) do
		m.map(binds, cb, desc)
	end
end

local map = M.map

function M.default()
	-- Custom keybind for our own help mode
	map(
		'a',
		{ 'F1', 'h' },
		function() require('swi.api.help').enabled = not require('swi.api.help').enabled end,
		'Toggle help'
	)

	-- Global keybinds
	map('a', 'Return', function() swi.mode = swi.mode == 'gallery' and 'viewer' or 'gallery' end, 'Toggle viewer')
	map('a', 'Escape', swi.exit, 'Exit application')
	map('a', 's', function() swi.mode = swi.mode == 'slideshow' and 'viewer' or 'slideshow' end, 'Toggle slideshow')
	map('a', 'Insert', function() l.marked.set_current 'toggle' end, 'Toggle mark on current entry')
	map('a', 'f', function() swi.fullscreen = nil end, 'Toggle fullscreen')
	map('a', 'a', function() swi.antialiasing = not swi.antialiasing end, 'Toggle antialiasing')

	-- Gallery
	-- scale
	map(
		'g',
		{ '=', '+', 'Ctrl+ScrollUp' },
		function() g.thumb_size = math.floor(g.thumb_size * 1.1 + 0.5) end,
		'Increase thumbnail size'
	)
	map(
		'g',
		{ '-', 'Ctrl+ScrollDown' },
		function() g.thumb_size = math.floor(g.thumb_size / 1.1 + 0.5) end,
		'Decrease thumbnail size'
	)
	-- image selection
	map('g', 'Home', g.go.first, 'Select first thumbnail')
	map('g', 'End', g.go.last, 'Select last thumbnail')
	map('g', { 'Left', 'ScrollLeft' }, g.go.left, 'Select thumbnail left')
	map('g', { 'Right', 'ScrollRight' }, g.go.right, 'Select thumbnail right')
	map('g', { 'Up', 'ScrollUp' }, g.go.up, 'Select thumbnail up')
	map('g', { 'Down', 'ScrollDown' }, g.go.down, 'Select thumbnail down')
	map('g', 'PageDown', g.go.pgdown, 'Page down in thumbnails')
	map('g', 'PageUp', g.go.pgup, 'Page up in thumbnails')
	-- text layer
	map('g', 't', function() t.enabled = not t.enabled end, 'Toggle text overlay')
	-- mouse bindings as keys
	map('g', 'MouseLeft', function() swi.mode = 'viewer' end, 'Switch to viewer mode with left mouse button')

	-- Viewer
	-- Image transforms
	map('v', '[', function() v.rotate(270) end, 'Rotate image 270° (left)')
	map('v', ']', function() v.rotate(90) end, 'Rotate image 90° (right)')
	map('v', 'm', v.flip_vertical, 'Flip image vertically')
	map('v', 'Shift+m', v.flip_horizontal, 'Flip image horizontally')
	-- Text overlay toggle
	map('v', 't', function() t.enabled = not t.enabled end, 'Toggle text overlay')
	-- Image navigation
	map('v', 'PageDown', v.go.prev, 'Next image')
	map('v', 'PageUp', v.go.next, 'Previous image')
	-- Frame navigation
	map('v', 'Shift+PageDown', v.next_frame, 'Next frame')
	map('v', 'Shift+PageUp', v.prev_frame, 'Previous frame')
	-- Scale (zoom)
	map('v', { '=', '+', 'Ctrl+ScrollUp' }, function() v.scale = v.get_abs_scale() * 1.1 end, 'Zoom in')
	map('v', { '-', 'Ctrl+ScrollDown' }, function() v.scale = v.get_abs_scale() / 1.1 end, 'Zoom out')
	map('v', 'BackSpace', v.reset, 'Reset scale and position')
	-- Image position / panning
	map('v', 'Left', v.step.left, 'Move left')
	map('v', 'Right', v.step.right, 'Move right')
	map('v', 'Up', v.step.up, 'Move up')
	map('v', 'Down', v.step.down, 'Move down')
	map('v', 'ScrollUp', function() v.step.up(20) end, 'Pan up')
	map('v', 'ScrollDown', function() v.step.down(20) end, 'Pan down')
	map('v', 'ScrollLeft', function() v.step.left(20) end, 'Pan left')
	map('v', 'ScrollRight', function() v.step.right(20) end, 'Pan right')
	-- Mouse zoom (centered at pointer)
	map('v', 'Ctrl+ScrollUp', function()
		local s = v.get_abs_scale() * 1.1
		local m = swi.get_mouse_pos()
		v.scale_centered(s, m.x, m.y)
	end, 'Zoom in at pointer')
	map('v', 'Ctrl+ScrollDown', function()
		local s = v.get_abs_scale() / 1.1
		local m = swi.get_mouse_pos()
		v.scale_centered(s, m.x, m.y)
	end, 'Zoom out at pointer')
end

return M
