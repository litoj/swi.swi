---@diagnostic disable: invisible
local e = require 'swi.api.eventloop'
local U = require 'swi.utils'
local mode_base = require 'swi.api.mode_base'

---@class swi.api.viewer: swi.viewer
---@field _api swayimg.viewer
---@field _last {w:integer,h:integer,x:integer,y:integer}|false
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

function M.set_default_scale(self, x)
	if x:sub(1, 8) == 'keep_by_' then
		if not ({ width = 1, height = 1, size = 1 })[x:sub(9)] then error('Invalid default scale: ' .. x) end
		x = 'keep'
		self._last = { s = 0, x = 0, y = 0 }
		e.subscribe {
			event = 'ImgChangePre',
			group = '_cust_default_scale',
			callback = function(state)
				local i = state.data
				---@diagnostic disable-next-line: assign-type-mismatch
				self._last = self._api.get_position()
				self._last.w = i.width
				self._last.h = i.height
			end,
		}
	else
		e.unsubscribe { group = '_cust_default_scale' }
		self._last = false
	end
	self._api.set_default_scale(x)
end

function M.set_scale(self, x)
	if type(x) == 'string' then
		self._api.set_fix_scale(x)
	else
		self._api.set_abs_scale(x)
	end
end
function M.get_scale(self)
	local val = rawget(self, '_scale') or rawget(self, '_default_scale')
	if type(val) == 'string' and val:sub(1, 4) == 'keep' then return self._api.get_scale() end
	return val
end

function M.set_position(self, x)
	if type(x) == 'string' then
		self._api.set_fix_position(x)
	else
		self._api.set_abs_position(x.x, x.y)
	end
end

function M.set_img_bg(self, x)
	if type(x) == 'table' then
		self._api.set_image_chessboard(x.size, x[1], x[2])
	else
		self._api.set_image_background(x)
	end
end

---@param api_name 'viewer'|'slideshow'
function M.new(api_name)
	local api = swayimg[api_name] ---@type swayimg.viewer
	---@diagnostic disable-next-line: missing-fields
	local self = { _api = api, _default_scale = 'optimal', _last = false } ---@type swi.api.viewer

	self._overrides = {
		default_scale = { set = M.set_default_scale },
		scale = { set = M.set_scale, get = M.get_scale },
		position = { set = M.set_position },
		image_background = { set = M.set_img_bg },
		preload_limit = { set = function(self, x) self._api.limit_preload(x) end },
		history_limit = { set = function(self, x) self._api.limit_history(x) end },
	}

	api.on_image_change(function()
		local last = self._last
		local img = last and api.get_image() or U.lazy(api.get_image)
		e.trigger { event = 'ImgChange', mode = api_name, data = img }

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

	self.get_abs_scale = api.get_scale
	self.go = M.new_go(api)
	self.step = M.new_step(self)
	self.scale_centered = function(s, x, y)
		api.set_abs_scale(s, x, y)
		rawset(self, '_scale', s)
	end

	return mode_base.new(self, api_name)
end

return M
