---@diagnostic disable: invisible
---@module 'swi.api.viewer'

local e = require 'swi.api.eventloop'
local U = require 'swi.lib.utils'
local mode_base = require 'swi.api.mode_base'
local mode_text = require 'swi.api.mode_text'

---@class swi.api.viewer: swi.viewer, swi.api.mode_base
---@field _api swayimg.viewer
---@field _last {w:integer,h:integer,x:integer,y:integer}|false
---@field text swi.api.mode_text
local M = {}

---@return swi.viewer.panner
function M.new_panner(self)
	local pan
	pan = {
		default_size = 50,
		by = function(x, y)
			local p = self.position
			self.position = { x = p.x - x, y = p.y - y }
		end,
		left = function(p) pan.by(-(p or pan.default_size), 0) end,
		right = function(p) pan.by((p or pan.default_size), 0) end,
		up = function(p) pan.by(0, -(p or pan.default_size)) end,
		down = function(p) pan.by(0, (p or pan.default_size)) end,
	}

	return pan
end

function M.new_go(api, api_name)
	return setmetatable({}, {
		__index = function(tbl, idx)
			tbl[idx] = function()
				e.trigger { event = 'ImgChangePre', mode = api_name, match = api_name, data = U.lazy(api.get_image) }
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
		self._last = { w = 0, h = 0, x = 0, y = 0 }
		e.subscribe {
			event = 'ImgChangePre',
			mode = self.text._api_name,
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
		e.unsubscribe { group = '_cust_default_scale', match = self.text._api_name }
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
---@return swi.viewer|swi.slideshow
function M.new(api_name)
	local api = swayimg[api_name] ---@type swayimg.viewer
	local self = {
		_api = api,
		_last = false,

		--- https://github.com/artemsen/swayimg/blob/master/src/viewer.cpp#L29
		_centering = true,
		_loop = true,
		_default_position = 'center',
		_image_background = { 0xff333333, 0xff4c4c4c, size = 20 }, -- chessboard
	}

	if api_name == 'viewer' then
		self._default_scale = 'optimal'
		self._window_background = 0xff000000
		self._history_limit = 1
		self.text = mode_text.new {
			_api = api,
			_api_name = api_name,
			_topleft = {
				'File:\t{name}',
				'Format:\t{format}',
				'File size:\t{sizehr}',
				'File time:\t{time}',
				'EXIF date:\t{meta.Exif.Photo.DateTimeOriginal}',
				'EXIF camera:\t{meta.Exif.Image.Model}',
			},
			_topright = {
				'Image:\t{list.index} of {list.total}',
				'Frame:\t{frame.index} of {frame.total}',
				'Size:\t{frame.width}x{frame.height}',
			},
			_bottomleft = { 'Scale: {scale}' },
			_bottomright = {},
		}
	else --- https://github.com/artemsen/swayimg/blob/master/src/slideshow.cpp#L17
		self._default_scale = 'fit'
		self._window_background = 'auto'
		self._history_limit = 0
		self.text = mode_text.new {
			_api = api,
			_api_name = api_name,
			_topleft = {},
			_topright = { '{name}' },
			_bottomleft = {},
			_bottomright = {},
		}
	end

	---@cast self swi.api.viewer

	self.get_abs_scale = api.get_scale
	self.go = M.new_go(api)
	self.pan = M.new_panner(self)
	self.scale_centered = function(s, x, y)
		api.set_abs_scale(s, x, y)
		rawset(self, '_scale', s)
	end
	self.open = function(path)
		e.trigger { event = 'ImgChangePre', mode = api_name, match = api_name, data = U.lazy(api.get_image) }
		api.open(path)
		e.trigger { event = 'OptionSet', mode = api_name, match = 'swi.imagelist.size', data = swi.imagelist.size() }
	end

	self._overrides = {
		default_scale = { set = M.set_default_scale },
		scale = { set = M.set_scale, get = M.get_scale },
		position = { set = M.set_position },
		image_background = { set = M.set_img_bg },
		preload_limit = {
			set = function(self, x)
				x = math.floor(x)
				self._api.limit_preload(x)
				rawset(self, '_preload_limit', x)
				return true
			end,
		},
		history_limit = {
			set = function(self, x)
				x = math.floor(x)
				self._api.limit_history(x)
				rawset(self, '_history_limit', x)
				return true
			end,
		},
	}

	api.on_image_change(function()
		local last = self._last
		local img = last and api.get_image() or U.lazy(api.get_image)
		e.trigger { event = 'ImgChange', mode = api_name, match = api_name, data = img }

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

	self = mode_base.new(self, api_name) ---@type swi.api.viewer

	return self
end

return M
