local M = {}

function M.load_dir_if_single()
	e.subscribe {
		event = 'SwiEnter',
		callback = function()
			if l.size() == 1 then l.add(l.get_current().path:match '.+/') end
			return true
		end,
	}
end

function M.print_option_changes(deregister)
	if deregister then
		e.unsubscribe { event = 'OptionSet', group = 'change_printer' }
		return
	end

	local function register_printer()
		-- register after base config has been loaded
		e.subscribe { -- Print messages on option update
			event = 'OptionSet',
			pattern = { '!swi.imagelist.size', '^swi%.?[^.]*%.[^.]*$' }, -- all main opts - not the subsubtables (text etc.)
			group = 'change_printer',
			callback = function(state)
				local v = state.data
				if type(v) == 'number' then
					v = string.format('%.2f', v)
				elseif type(v) == 'table' then -- ignore window size and position changes
					return
				end

				local name = state.match:match '([^.]+%.[^.]+)$'
				t.set_status(
					('%s%s: %s'):format(
						name:sub(1, 1):upper(),
						name:sub(2):gsub('[_.](.)', function(x) return ' ' .. x:upper() end),
						v
					)
				)
			end,
		}

		return true
	end

	if rawget(swi, '_initialized') then
		register_printer()
	else
		e.subscribe { event = 'SwiEnter', callback = register_printer }
	end
end

function M.resize_image_with_window()
	e.subscribe {
		event = 'WinResized',
		mode = { 'viewer', 'slideshow' },
		callback = function()
			if type(v.scale) == 'string' then swayimg.viewer.set_fix_scale(v.scale) end
		end,
	}
end

function M.print_shell_output()
	e.subscribe {
		event = 'ShellCmdPost',
		callback = function(state) t.set_status(state.data.out) end,
	}
end

function M.cycle_values(values, current)
	for i, mode in ipairs(values) do
		if mode == current then return values[i % #values + 1] end
	end
end

function M.cycle_scale()
	local api = swi[swi.mode]
	local modes = {
		'optimal',
		'width',
		'height',
		'fit',
		'fill',
		'real',
		'keep',
		'keep_by_width',
		'keep_by_height',
		'keep_by_size',
	}

	local current = type(api.scale) == 'string' and api.scale or 'keep'
	api.scale = M.cycle_values(modes, current)
end

function M.cycle_position()
	local api = swi[swi.mode]
	local modes = {
		'center',
		'topcenter',
		'leftcenter',
		'rightcenter',
		'bottomcenter',
		'topleft',
		'topright',
		'bottomleft',
		'bottomright',
	}

	local current = type(api.position) == 'string' and api.position or 'center'
	api.position = M.cycle_values(modes, current)
end

return M
