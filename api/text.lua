---@diagnostic disable: invisible
---@module 'swi.api.text'
---@class swi.api.text: swi.text
local M = {
	_api = swayimg.text,
	_path = 'swi.text',

	_font = 'monospace',
	_size = 24,

	_enabled = true,
	_status_timeout = 3,
	_line_spacing = 1,
	_padding = 10,
	_foreground = 0xffcccccc,
	_background = 0x00000000,
	_shadow = 0xd0000000,
}

M.is_visible = swayimg.text.visible

---@param self swi.api.text
local function set_enabled(self, val)
	if val == true then
		self._api.show()
		self._api.set_timeout(0)
	elseif val == false then
		self._api.hide()
	else
		self._api.set_timeout(val)
	end
end

-- transform scale factor into a pixel value
---@param self swi.api.text
local function set_spacing(self, val) self._api.set_spacing(math.floor((val - 1) * self._size)) end
---@param self swi.api.text
local function set_size(self, val)
	self._api.set_size(val)

	-- update line spacing
	self._size = val
	set_spacing(self, self._line_spacing)
	return true
end

M._overrides = {
	enabled = { set = set_enabled },
	line_spacing = { set = set_spacing },
	size = { set = set_size },
}

return require('swi.api.proxy').new(M)
