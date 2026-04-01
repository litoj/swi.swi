local proxy = require 'swi.api.proxy'
local e = require 'swi.api.eventloop'
local U = require 'swi.utils'
local mode_base = require 'swi.api.mode_base'

local M = {}

function M.new_step(self)
	local step
	step = {
		default_size = 50,
		by = function(x, y)
			local p = self.position
			self.position = { x = p.x - x, y = p.y - y }
		end,
		left = function(p) step.by(-(p or step.default_size), 0) end,
		right = function(p) step.by((p or step.default_size), 0) end,
		up = function(p) step.by(0, -(p or step.default_size)) end,
		down = function(p) step.by(0, (p or step.default_size)) end,
	}

	return step
end

function M.new_go(api)
	return setmetatable({}, {
		__index = function(tbl, idx)
			tbl[idx] = function()
				e.trigger { event = 'ImgChangePre', data = U.lazy(api.get_image) }
				api.switch_image(idx)
			end
			return tbl[idx]
		end,
	})
end

---@param name 'viewer'|'slideshow'
function M.new(name)
	local api = swayimg[name] ---@type swayimg.viewer
	local o = mode_base.new_overrides(api, name)
	local self = { _overrides = o, _default_scale = 'optimal' }

	---@alias lastimg {w:integer,h:integer,x:integer,y:integer}?
	local last

	o.default_scale = {
		set = function(x)
			if x:sub(1, 8) == 'keep_by_' then
				if not ({ width = 1, height = 1, size = 1 })[x:sub(9)] then error('Invalid default scale: ' .. x) end
				x = 'keep'
				last = { s = 0, x = 0, y = 0 }
				e.subscribe {
					event = 'ImgChangePre',
					group = '_cust_default_scale',
					callback = function(state)
						local i = state.data
						last = api.get_position() ---@type lastimg
						last.w = i.width
						last.h = i.height
					end,
				}
			else
				e.unsubscribe { group = '_cust_default_scale' }
				last = nil
			end
			api.set_default_scale(x)
		end,
	}
	self.scale_centered = function(s, x, y)
		api.set_abs_scale(s, x, y)
		rawset(self, '_scale', s)
	end
	self.get_abs_scale = api.get_scale
	o.scale = {
		set = function(x)
			if type(x) == 'string' then
				api.set_fix_scale(x)
			else
				api.set_abs_scale(x)
			end
		end,
		get = function(self)
			local val = rawget(self, '_scale') or rawget(self, '_default_scale')
			if type(val) == 'string' and val:sub(1, 4) == 'keep' then return api.get_scale() end
			return val
		end,
	}
	o.position = {
		set = function(x)
			if type(x) == 'string' then
				api.set_fix_position(x)
			else
				api.set_abs_position(x.x, x.y)
			end
		end,
	}

	api.on_image_change(function()
		local img = last and api.get_image() or U.lazy(api.get_image)
		e.trigger { event = 'ImgChange', mode = name, data = img }

		rawset(self, '_scale', nil)
		if not last then return end

		---@diagnostic disable-next-line: undefined-field
		local mode = self._default_scale:sub(9)

		local f
		if mode == 'width' then
			f = last.w / img.width
		elseif mode == 'height' then
			f = last.h / img.height
		elseif mode == 'size' then
			f = (last.w + last.h) / (img.width + img.height)
		end
		api.set_abs_scale(api.get_scale() * f, 0, 0)
		api.set_abs_position(last.x, last.y)
	end)

	o.image_background = {
		set = function(x)
			if type(x) == 'table' then
				api.set_image_chessboard(x.size, x[1], x[2])
			else
				api.set_image_background(x)
			end
		end,
	}
	o.preload_limit = { set = api.limit_preload }
	o.history_limit = { set = api.limit_history }

	self.go = M.new_go(api)
	self.step = M.new_step(self)

	return proxy('swi.' .. name, api, self)
end

return M
