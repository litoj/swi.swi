---@diagnostic disable: invisible
---@module 'swi.api.pager'

local e = swi.eventloop
local proxy = require 'swi.api.proxy'
local U = require 'swi.utils'

-- Paging object to manage scrollable output
---@class swi.api.pager: proxy
---@field mode appmode_t in which mode should we set the data
---@field position block_position_t where should we output to
---@field title string title in the non-scrollable header
---@field lines string[] the output to be paged
---Whether to activate or deactivate the pager.
---Configure all the preceding definition fields before enabling.
---@field enabled boolean
---@field page integer
---@field page_size integer
---@field total_pages integer
---@field line integer
local M = {
	_path = 'pager', ---@private
	_overrides = {}, ---@private
	_trigger = false, ---@private
	_on_mode_change = function() end, ---@private

	---@type mode_base.text
	---@diagnostic disable-next-line: assign-type-mismatch
	_mode_text = false, ---@private
	_enabled = false, ---@private
	---@type block_position_t
	_position = 'topleft', ---@private
	---@type extended_text_template[]|false
	_original_text = false, ---@private

	_title = '', ---@private
	---@type string[]
	_lines = {}, ---@private

	_line = 1, ---@private
	_page = 1, ---@private

	_page_size = 20, ---@private
	_total_pages = 1, ---@private

	---@type string[]
	_last_render = {}, ---@private
	_last_start = -1, ---@private
	_last_end = 0, ---@private

	size_factor = 0.75,
}

function M:prepare_renderer()
	self._last_render = {}
	local out = self._last_render
	for i, v in ipairs(self._lines) do
		out[i] = v
	end
	out[#out + 1] = '' -- to keep the size and make pairs() traverse it in order - as an array
	self._last_start = 2 -- to ensure the initial sizes differ and hence will cause an update
	self._last_end = #self._lines
end

function M:render(force)
	if not self._enabled then return end

	local lines = self._lines
	local from = self._line
	local to = math.min(#lines, from + self._page_size - 1)
	local ls, le = self._last_start, self._last_end
	if ls == from and le == to then
		if force then self._mode_text[self._position] = self._last_render end
		return
	end

	local out = self._last_render
	out[0] = ('%s[%d/%d]'):format(self._title, self._page, self._total_pages)

	if from > ls then
		local _end = math.min(from - 1, le)
		for i = ls, _end do
			out[i] = nil
		end
		self._last_start = from
		if le > from then from = le + 1 end
	elseif ls < to then
		for i = from, ls - 1 do
			out[i] = lines[i]
		end
		self._last_start = from
		from = le + 1
	else
		self._last_start = from
	end

	if to < le then
		local start = math.max(to + 1, ls)
		for i = start, le do
			out[i] = nil
		end
		self._last_end = to
		if ls <= to then to = ls - 1 end
	elseif le > from then
		for i = le + 1, to do
			out[i] = lines[i]
		end
		self._last_end = to
		to = ls - 1
	else
		self._last_end = to
	end

	for i = from, to do
		out[i] = lines[i]
	end

	self._mode_text[self._position] = out
	-- self._mode_text._api.set_text(self._position, out)
end

---@private
function M:_restore_original()
	if self._original_text then
		self._mode_text[self._position] = self._original_text
		self._original_text = false
	end
end

---@private
function M:_on_dst_change()
	if self._mode_text then
		self._original_text = self._mode_text[self._position]
		-- nullify the text to then set it directly without any possible side-updates from prev events
		-- self._mode_text[self._position] = {}
		self:render(true)
	end
end

---@private
---Update the renderer with minimum work.
---@param resize boolean does the screen need redrawing
---@param reset boolean should we redraw all data, not just the resized amount
function M:recalibrate(resize, reset)
	if resize then
		local size = swi.text.size
		local spacing = swi.text.line_spacing
		local linepx = math.floor(spacing * size) + size * M.size_factor
		local height = swi.get_window_size().height
		self._page_size = math.floor(height / linepx) - 1 -- -1 for header
	end

	if resize or reset then
		self._total_pages = math.max(1, math.ceil(#self._lines / self._page_size))
		self._page = math.floor((self._line - 1) / self._page_size) + 1
	end

	if reset then self:prepare_renderer() end

	self:render(true)
end

---Make multiple changes simultaneously and render only once at the end.
---@param applicator fun(it:swi.api.pager)
function M:bulk_change(applicator)
	if not self._enabled then return applicator(self) end
	---@type false|fun(self,val):boolean?
	local set_enable = self._overrides.enabled.set
	self._overrides.enabled.set = function(self, val)
		if val == false then
			self._overrides.enabled.set = set_enable
			set_enable = false
		end
		return false
	end

	self._enabled = false
	applicator(self)
	self._enabled = true
	if set_enable then
		self._overrides.enabled.set = set_enable
		self:recalibrate(false, true)
	else
		self.enabled = false
	end
end

M._overrides.mode = {
	---@param self swi.api.pager
	---@param mode appmode_t
	set = function(self, mode)
		self:_restore_original()
		self._mode_text = swi[mode].text
		self:_on_dst_change()
		return false
	end,
	get = function(self)
		return ({ [swi.viewer.text] = 'viewer', [swi.slideshow.text] = 'slideshow', [swi.gallery.text] = 'gallery' })[self._mode]
	end,
}

M._overrides.position = {
	---@param self swi.api.pager
	---@param position block_position_t
	set = function(self, position)
		self:_restore_original()
		self._position = position
		self:_on_dst_change()
		return false
	end,
}

M._overrides.title = {
	---@param self swi.api.pager
	---@param title string
	set = function(self, title)
		self._title = title
		self:render()
	end,
}

M._overrides.lines = {
	---@param self swi.api.pager
	---@param lines string[]
	set = function(self, lines)
		self._lines = lines
		if self._enabled then self:recalibrate(false, true) end
		return false
	end,
}

M._overrides.line = {
	---@param self swi.api.pager
	---@param linenr integer
	set = function(self, linenr)
		if #self._lines == 0 then return false end
		--- sets max to the beginning of last page
		-- self._line = math.max(1, math.min(self._page_size * (self._total_pages - 1) + 1, linenr))
		--- sets max to leave max 1 line empty at the end
		self._line = math.max(1, math.min(#self._lines - self._page_size + 2, linenr))
		self._page = math.floor((self._line - 1) / self._page_size) + 1
		self:render()
		return false
	end,
}

M._overrides.page = {
	---@param self swi.api.pager
	---@param pagenr integer
	set = function(self, pagenr)
		self._overrides.line.set(self, (pagenr - 1) * self._page_size + 1)
		return false
	end,
}

M._overrides.enabled = {
	---@param self swi.api.pager
	set = function(self, val)
		if val == self._enabled then return end
		self._enabled = val
		if val then
			self:recalibrate(true, true)

			-- Listen for WinResized and OptionSet updates to recalculate per_page and re-render pager
			local function recal(e) self:recalibrate(true, false) end
			rawset(self, '_hooks', {
				e.subscribe {
					event = 'WinResized',
					callback = recal,
				},
				e.subscribe {
					event = 'OptionSet',
					pattern = { 'swi.text.size', 'swi.text.line_spacing' },
					callback = recal,
				},
			})
		else
			for _, v in ipairs(rawget(self, '_hooks')) do
				e.unsubscribe { id = v }
			end

			self:_restore_original()
		end
		return false
	end,
}

---@param modes appmode_t|appmode_t[] in which modes are we allowed to change content
---@return swi.api.pager
function M.new(modes) return proxy.new(U.soft_copy(M)) end

return M
