local proxy = require 'swi.api.proxy'
local e = require 'swi.api.eventloop'

---@type swi
---@diagnostic disable-next-line: missing-fields
local M = { _overrides = {}, initialized = false }

do
	local viewer_proxy = require('swi.api.viewer').new
	M.viewer = viewer_proxy 'viewer'
	M.slideshow = viewer_proxy 'slideshow'
end

do
	local gallery_api = swayimg.gallery
	local g = { _overrides = require('swi.api.mode_base').new_overrides(gallery_api, 'gallery') }
	g._overrides.cache_limit = { set = gallery_api.limit_cache }
	g.go = setmetatable({}, {
		__index = function(tbl, idx)
			tbl[idx] = function() gallery_api.switch_image(idx) end
			return tbl[idx]
		end,
	})
	M.gallery = proxy('swi.gallery', gallery_api, g)

	e.subscribe { -- ad-hoc registering for when user wants to subscribe
		event = 'Subscribed',
		mode = 'gallery',
		pattern = 'ImgChange',
		callback = function()
			gallery_api.on_image_change(
				function() e.trigger { event = 'ImgChange', mode = 'gallery', data = gallery_api.get_image() } end
			)
			return true
		end,
	}
end

M.imagelist = require 'swi.api.imagelist'

do
	local text_api = swayimg.text
	M.text = proxy('swi.text', text_api, {
		enabled = {
			set = function(val)
				if val == true then
					text_api.show()
					text_api.set_timeout(0)
				elseif val == false then
					text_api.hide()
				else
					text_api.set_timeout(val)
				end
			end,
		},
		is_visible = text_api.visible,

		_line_spacing = 1,
		line_spacing = {
			-- transform scale factor into a pixel value
			set = function(val, self) text_api.set_spacing(math.floor((val - 1) * self._size)) end,
		},
		_size = 15,
		size = {
			set = function(val, self)
				text_api.set_size(val)

				-- update line spacing
				rawset(self, '_size', val)
				self.line_spacing = self.line_spacing
			end,
		},
	})
end

M.eventloop = e
---@diagnostic disable-next-line: invisible
M._overrides.mode = {
	set = function(v)
		local m = swayimg.get_mode()
		swayimg.set_mode(v)
		e.trigger { event = 'ModeChanged', mode = m, match = v }
	end,
}

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
	e.trigger { event = 'ShellCmdPost', data = { cmd = cmd, out = out } }
end

swayimg.on_window_resize(function()
	local ws = swayimg.get_window_size()
	local ows = rawget(swi, '_window_size')
	if not ows or ows.width ~= ws.width or ows.height ~= ws.height then
		-- TODO: find a way to distinguish focus events from resizing (both can happen at once)
		e.trigger { event = 'WinResized', data = ws }
		rawset(swi, '_window_size', ws)
	end
end)

---@type swi
_G.swi = proxy('swi', swayimg, M)

return M
