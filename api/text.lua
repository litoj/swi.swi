---@class swi.api.text: swi.text
local M = { _api = swayimg.text, _path = 'swi.text', _line_spacing = 1, _size = 15 }

M.is_visible = swayimg.text.visible
M._overrides = {
	line_spacing = {
		-- transform scale factor into a pixel value
		set = function(self, val) self._api.set_spacing(math.floor((val - 1) * self._size)) end,
	},
	size = {
		set = function(self, val)
			self._api.set_size(val)

			-- update line spacing
			self._size = val
			self.line_spacing = self.line_spacing
		end,
	},

	enabled = {
		set = function(self, val)
			if val == true then
				self._api.show()
				self._api.set_timeout(0)
			elseif val == false then
				self._api.hide()
			else
				self._api.set_timeout(val)
			end
		end,
	},
}

return require('swi.api.proxy').new(M)
