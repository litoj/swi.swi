---@module 'sai.mode.help'

local U = require 'sai.lib.utils'
local pager = require 'sai.lib.pager'
local binds = require('sai.binds').help

---Fully generated tab.
---@class help_tab
---@field title string
---@field lines extended_text_template[]
---Tab generator: called on activation and on every mode change; generates
---all tabs straight-up - return a fresh list to add or remove tabs.
---@alias help_tabs fun(self:sai.mode.help):help_tab[]

---Generic paged help overlay with tabbed content.
---@class sai.mode.help: sai.lib.remapper
---@field enabled boolean
---@field pager sai.lib.pager
---@field tab integer which tab are we on
---@field tabs help_tabs
local M = {
	super = require 'sai.lib.remapper',
	persist_mode_change = true,

	_tab = 1, ---@protected
	---@type help_tab[]
	_tabs = {}, ---@protected cache

	tabs = function() return {} end,
}

---Create an instance (see sai.mode.key_help / sai.mode.var_help) by calling
---`help.new { _path = ..., tabs = ... }` - the passed table becomes the instance.
---@param self sai.mode.help
---@return sai.mode.help
function M:new()
	U.new_object(self, M)
	M.super.new(self) -- the sai tree first: the pager writes through it
	binds(self)

	-- the pager writes through the mode's own text tree: one shared layer,
	-- so the mode's takeover does not blank its own header
	rawset(
		self,
		'pager',
		pager.new {
			_path = self._path .. '.pager',
			_trigger = true,
			_location = 'topleft',
			sai_text = self.sai.text,
		}
	)

	self.sai.eventloop.subscribe {
		event = 'User',
		pattern = { 'ModePush', 'ModePop' },
		callback = function(ev)
			if ev.data == self then return end
			self:_on_mode_change(ev)
		end,
	}
	-- make the image a small backdrop for the help text
	self.sai.viewer.default_scale = 'keep_width'
	self.sai.slideshow.default_scale = 'keep_width'
	local gspace = sai.gallery.thumb_size + sai.gallery.padding_size
	self.sai.gallery(function(g)
		g.thumb_size = gspace / 3
		g.padding_size = gspace / 3
		g.cache_size = 0
		g.preload = false
	end)

	return self
end

function M:set_tab(idx)
	local tabs = self.tabs(self)
	if not tabs[1] then return false end
	self._tabs = tabs
	self._tab = (idx - 1) % #tabs + 1

	local tab = tabs[self._tab]
	self.pager:bulk_change(function(pager)
		-- without the mode's own binds there is no way to switch tabs
		pager.title = self._enabled and ('[Tab %d/%d] %s\t'):format(self._tab, #tabs, tab.title) or (tab.title .. '\t')
		pager.lines = tab.lines
		pager.line = 1
	end)
	return true
end

---@param ev event.ModeChanged|event.User
function M:_on_mode_change(ev)
	if ev.event == 'User' then -- custom layer change (ModePush/ModePop)
		self:set_tab(1) -- regenerate the tabs, land on the first
		return false
	end
	if ev.event == 'ModeChangedPre' then self.pager.enabled = false end
	M.super._on_mode_change(self, ev) -- re-apply our binds on the new mode first
	if ev.event == 'ModeChanged' then
		self.pager.enabled = true
		self:set_tab(self._tab) -- tab contents may differ per mode
	end
	return false
end

function M:set_enabled(val)
	if val == self._enabled then return true end
	if val then
		local mode = sai.mode
		--- 100px
		if mode ~= 'gallery' then self.sai[mode].scale = 100 / sai[mode].get_image().width end

		M.super.set_enabled(self, val) -- register our bind layer first
		self.tab = self._tab -- re-render the current tab, keep its number
	else
		self.pager.enabled = false
		M.super.set_enabled(self, val) -- the ModePop hook re-derives the display
		return true
	end

	self.pager.enabled = val
	return true
end

return M
