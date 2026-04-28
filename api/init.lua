---@diagnostic disable: invisible
---@module 'swi.api.init'

local proxy = require 'swi.lib.proxy'
local e = require 'swi.api.eventloop'

---@type swi
---@diagnostic disable-next-line: missing-fields
local M = {
	_api = swayimg,
	_path = 'swi',
	_overrides = {},
	initialized = false,

	_overlay = false, -- enabled by default in sway and disabled otherwise
	_exif_orientation = true, -- automatically applied only to raw files
	_antialiasing = true,
	_decoration = true,
	_dnd_button = 'MouseRight',
	_apply_raw_wb = true,
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

M._overrides.apply_raw_wb = {
	set = function(self, v) self._api.set_format_params('raw', { camera_wb = v }) end,
}

-- ensure even the default keymappings trigger our events by redefining the defaults
_G.swi = proxy.new(M)

local x

swayimg.on_window_resize(function()
	if x then
		local ws = swayimg.get_window_size()
		local ows = M._old_winsize
		if ows.width ~= ws.width or ows.height ~= ws.height then
			-- TODO: find a way to distinguish focus events from resizing (both can happen at once)
			e.trigger { event = 'WinResized', data = ws }
			---@diagnostic disable-next-line: inject-field
			M._old_winsize = ws
		end
	else
		if x == nil and not swi.overlay then
			x = false
			return
		elseif x == false then
			x = swi[swi.mode]
			x.scale = x.default_scale -- fix incorrect initial size with overlay disabled
		end
		x = true
		swi.initialized = true
		rawset(M, '_old_winsize', swayimg.get_window_size())

		e.trigger { event = 'SwiEnter' }

		if e._hooks.SwiEnter then
			e._hooks.SwiEnter = nil

			-- easteregg
			local p = io.popen 'date +%d%m' or {}
			local o = p:read '*a'
			p:close()
			if o == '1003\n' then print [[Naughty, naughty! Didn't clean those hookers today...]] end
		end

		e.subscribe {
			event = 'Subscribed',
			pattern = 'SwiEnter',
			-- ensure all hooks expecting initialization get loaded
			-- (especially the lazy ones not checking swi.initialized)
			callback = function(h)
				h.data.callback()
				e._hooks.SwiEnter = nil
			end,
		}

		require('swi.binds').late_init_default()
	end
end)

return M
