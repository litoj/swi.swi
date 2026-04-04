---@diagnostic disable: invisible
---@module 'swi.api'

local proxy = require 'swi.api.proxy'
local e = require 'swi.api.eventloop'

---@type swi
---@diagnostic disable-next-line: missing-fields
local M = {
	_api = swayimg,
	_path = 'swi',
	_overrides = {},
	initialized = false,

	_exif_orientation = true, -- automatically applied only to raw files
	_antialiasing = false,
	_decoration = true,
	_dnd_button = 'MouseRight',
}

M.eventloop = e
M.imagelist = require 'swi.api.imagelist'
M.text = require 'swi.api.text'
do
	local viewer_proxy = require('swi.api.viewer').new
	M.viewer = viewer_proxy 'viewer'
	M.slideshow = viewer_proxy 'slideshow'
end
M.gallery = require 'swi.api.gallery'

function M.exit(code)
	local ev = { event = 'SwiLeavePre', match = tostring(code), data = code }
	e.trigger(ev)
	if not next(e.get_subscribed(ev)) then swayimg.exit(code) end
end

-- TODO: how to make stderr appear? 2>&1 doesn't work
---@param cmd string
function M.exec(cmd)
	local abort
	cmd = cmd:gsub('([^%%])%%([^%%])', function(a, type)
		if type == 'm' or type == 's' then
			local marked = M.imagelist.marked.get()

			if #marked > 0 then
				return ("%s'%s'"):format(a, table.concat(marked, "' '"))
			elseif type == 'm' then
				abort = true
				swayimg.text.set_status 'No marked files'
				return ''
			else -- type == 's'
				type = 'f'
			end
		end

		local path = M.imagelist.get_current().path
		if type == 'f' then
			return ("%s'%s'"):format(a, path)
		else
			return ('%s%s%s'):format(a, path, type)
		end
	end):gsub('%%%%', '%%')
	if abort then return end

	local p = io.popen(cmd, 'r')
	if not p then error('invalid command: ' .. cmd) end
	local out = p:read '*a'
	p:close()
	e.trigger { event = 'ShellCmdPost', match = cmd, data = out }
end

M._overrides.mode = {
	set = function(self, v)
		local m = self._api.get_mode()
		self._api.set_mode(v)
		e.trigger { event = 'ModeChanged', mode = v, match = ('%s:%s'):format(m:sub(1, 1), v:sub(1, 1)), data = m }
		return false
	end,
}

-- ensure even the default keymappings trigger our events by redefining the defaults
_G.swi = proxy.new(M)
require('swi.api.keymappings').default()

swayimg.on_window_resize(function()
	local ws = swayimg.get_window_size()
	local ows = rawget(M, '_old_winsize')
	if not ows or ows.width ~= ws.width or ows.height ~= ws.height then
		-- TODO: find a way to distinguish focus events from resizing (both can happen at once)
		e.trigger { event = 'WinResized', data = ws }
		rawset(M, '_old_winsize', ws)
	end
end)

return M
