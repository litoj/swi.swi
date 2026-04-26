---@module 'swi.binds'

local U = require 'swi.lib.utils'

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

---@type {[string]:{[integer]:swi.lib.keybind_processor|keybind_processor}}
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

function M.late_init_default()
	local deftrace = U.pretty_trace('default', debug.traceback())
	local function map(mode, binds, cb, desc)
		local cfg = { cb = cb, desc = desc, default = true, trace = deftrace, _traced = true }
		for _, m in ipairs(modemap[mode]) do
			for _, b in ipairs(U.tabled(binds)) do
				if not m._mappings[b] then
					m._mappings[b] = cfg
					m:_rawmap(b, cb)
				end
			end
		end
	end

	-- Custom keybind for our own help mode
	local h = require 'swi.api.help'
	modemap['h'] = { h }
	map('a', { 'F1', 'h' }, function() h.enabled = not h.enabled end, 'Toggle help')
	map('h', { 'Right', 'Tab' }, function() h.tab = h.tab + 1 end, 'Next help tab')
	map('h', { 'Left', 'Shift+ISO_Left_Tab' }, function() h.tab = h.tab - 1 end, 'Previous help tab')
	map('h', { 'Up', 'ScrollUp' }, function() h.pager.line = h.pager.line - 1 end, 'Scroll up')
	map('h', { 'Down', 'ScrollDown' }, function() h.pager.line = h.pager.line + 1 end, 'Scroll down')
	map('h', 'Prior', function() h.pager.line = h.pager.line - h.pager.page_size end, 'Page up')
	map('h', 'Next', function() h.pager.line = h.pager.line + h.pager.page_size end, 'Page down')
	map('h', { 'Escape', 'q' }, function() h.enabled = false end, 'Exit help overlay')

	-- Global keybinds
	map('a', 'Return', function() swi.mode = swi.mode == 'gallery' and 'viewer' or 'gallery' end, 'Toggle viewer')
	map('a', 'Escape', swi.exit, 'Exit application')
	map('a', 's', function() swi.mode = swi.mode == 'slideshow' and 'viewer' or 'slideshow' end, 'Toggle slideshow')
	map('a', 'Insert', function() l.marked.set_current 'toggle' end, 'Toggle mark on current entry')
	map('a', 'f', function() swi.fullscreen = not swi.fullscreen end, 'Toggle fullscreen')
	map('a', 'a', function() swi.antialiasing = not swi.antialiasing end, 'Toggle antialiasing')

	-- Gallery
	-- scale
	map(
		'g',
		{ 'equal', 'Shift+plus', 'Ctrl+ScrollUp' },
		function() g.thumb_size = math.floor(g.thumb_size * 1.1 + 0.5) end,
		'Increase thumbnail size'
	)
	map(
		'g',
		{ 'minus', 'Ctrl+ScrollDown' },
		function() g.thumb_size = math.floor(g.thumb_size / 1.1 + 0.5) end,
		'Decrease thumbnail size'
	)
	-- image selection
	local ggo = g.go
	map('g', 'Home', ggo.first, 'Go first')
	map('g', 'End', ggo.last, 'Go last')
	map('g', { 'Left', 'ScrollLeft' }, ggo.left, 'Go left')
	map('g', { 'Right', 'ScrollRight' }, ggo.right, 'Go right')
	map('g', { 'Up', 'ScrollUp' }, ggo.up, 'Go up')
	map('g', { 'Down', 'ScrollDown' }, ggo.down, 'Go down')
	map('g', 'Next', ggo.pgdown, 'Page down')
	map('g', 'Prior', ggo.pgup, 'Page up')
	-- text layer
	map('g', 't', function() t.enabled = not t.enabled end, 'Toggle text')
	-- mouse bindings as keys
	map('g', 'MouseLeft', function() swi.mode = 'viewer' end, 'Switch to viewer')

	-- Viewer
	-- Image transforms
	map('v', 'bracketleft', function() v.rotate(270) end, 'Rotate left')
	map('v', 'bracketright', function() v.rotate(90) end, 'Rotate right')
	map('v', 'm', v.flip_vertical, 'Flip vertical')
	map('v', 'Shift+m', v.flip_horizontal, 'Flip horizontal')
	-- Text overlay toggle
	map('v', 't', function() t.enabled = not t.enabled end, 'Toggle text')
	-- Image navigation
	map('v', 'Home', v.go.first, 'Go first')
	map('v', 'End', v.go.last, 'Go last')
	map('v', 'Next', v.go.next, 'Go next')
	map('v', 'Prior', v.go.prev, 'Go prev')
	-- Frame navigation
	map('v', 'Shift+Next', v.next_frame, 'Next frame')
	map('v', 'Shift+Prior', v.prev_frame, 'Previous frame')
	-- Scale (zoom)
	map('v', { 'equal', 'Shift+plus', 'Ctrl+ScrollUp' }, function() v.scale = v.get_abs_scale() * 1.1 end, 'Zoom in')
	map('v', { 'minus', 'Ctrl+ScrollDown' }, function() v.scale = v.get_abs_scale() / 1.1 end, 'Zoom out')
	map('v', 'BackSpace', v.reset, 'Reset scale and position')
	-- Image position / panning
	map('v', 'Left', v.step.left, 'Pan left')
	map('v', 'Right', v.step.right, 'Pan right')
	map('v', 'Up', v.step.up, 'Pan up')
	map('v', 'Down', v.step.down, 'Pan down')
	map('v', 'ScrollUp', function() v.step.up(20) end, 'Pan up 20px')
	map('v', 'ScrollDown', function() v.step.down(20) end, 'Pan down 20px')
	map('v', 'ScrollLeft', function() v.step.left(20) end, 'Pan left 20px')
	map('v', 'ScrollRight', function() v.step.right(20) end, 'Pan right 20px')
	-- Mouse zoom (centered at pointer)
	map('v', 'Ctrl+ScrollUp', function()
		local s = v.get_abs_scale() * 1.1
		local m = swi.get_mouse_pos()
		v.scale_centered(s, m.x, m.y)
	end, 'Zoom in on cursor')
	map('v', 'Ctrl+ScrollDown', function()
		local s = v.get_abs_scale() / 1.1
		local m = swi.get_mouse_pos()
		v.scale_centered(s, m.x, m.y)
	end, 'Zoom out at cursor')
end

return M
