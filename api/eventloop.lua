---@module 'swi.api.eventloop'

local U = require 'swi.utils'
local tabled = U.tabled

---@private
---@class swi.eventloop.hook: swi.eventloop.subscribe.opts
---@field pattern table<string|integer,string>
---@field mode string[]

---@type swi.eventloop
local M = {
	---@type {[event_name_t]:{[appmode_t]:{[hook_id]:swi.eventloop.hook}}}
	_hooks = {},
	debug_trigger = false,
	debug_subscribe = false,
}

local function print_debug(name, t)
	if t.event == 'Subscribed' and name == 'trigger' then return end
	local tbl = { event = t.event, mode = t.mode, match = t.match or t.pattern }
	print(U.pretty_trace(name, debug.traceback()), name, U.tbl_to_str(tbl, ''))
end

---@param cfg swi.eventloop.subscribe.opts
---@return swi.eventloop.hook
local function mk_hook(cfg)
	local t = tabled(cfg.pattern or {})
	local i = #t
	while i > 0 do
		local p = t[i]
		if p and not p:match '[*+?%%^$%[%]()]' then
			--- make direct matches into indexes
			if p:sub(1, 1) == '!' then
				t[p:sub(2)] = false
			else
				t[p] = true
			end
			table.remove(t, i)
		end
		i = i - 1
	end
	cfg.pattern = t ---@cast cfg swi.eventloop.hook
	return cfg
end

local function has_match(match, ptnlist)
	if not match or not next(ptnlist) then return true end
	local direct = ptnlist[match]
	if direct ~= nil then return direct end
	for _, p in ipairs(ptnlist) do
		if match:match(p) then return true end
	end
end

local modes = { 'viewer', 'gallery', 'slideshow' }
---@param f swi.eventloop.filter.opts
---@param on_match fun(h:swi.eventloop.hook,idx:hook_id,m:appmode_t,ev:event_name_t)
local function apply_filtered(f, on_match)
	local modes = tabled(f.mode or modes)
	for _, ev in pairs(tabled(f.event or U.rev_idx(M._hooks))) do
		local ev_hooks = M._hooks[ev]
		if ev_hooks then
			for _, m in pairs(modes) do
				local m_hooks = ev_hooks[m]
				if m_hooks then
					for i, hook in pairs(m_hooks) do
						local ok = has_match(f.match, hook.pattern)
						if f.id and ok then ok = f.id == i end
						if f.group and ok then ok = f.group == hook.group end
						if ok then on_match(hook, i, m, ev) end
					end
				end
			end
		end
	end
end

function M.unsubscribe(f)
	apply_filtered(f, function(_, id, m, ev)
		local ev_hooks = M._hooks[ev]
		local m_hooks = ev_hooks[m]
		local m_idx = next(m_hooks)
		if m_idx == id and not next(m_hooks, m_idx) then
			local ev_idx = next(ev_hooks)
			if ev_idx == m and not next(ev_hooks, ev_idx) then
				M._hooks[ev] = nil
			else
				ev_hooks[m] = nil
			end
		else
			m_hooks[id] = nil
		end
	end)
end

function M.get_subscribed(f)
	local t = {}
	apply_filtered(f or {}, function(h, id) t[id] = h end)
	return t
end

function M.trigger(state)
	if M.debug_trigger then print_debug('trigger', state) end

	---@cast state swi.eventloop.filter.opts
	state.mode = state.mode or swayimg.get_mode()
	apply_filtered(state, function(hook)
		local ok, ret = xpcall(hook.callback, debug.traceback, state)
		if not ok then
			---@diagnostic disable-next-line: param-type-mismatch
			swayimg.text.set_status(string.gsub(ret, '\t', '  '))
			print(ret)
		elseif ret then
			M.unsubscribe { id = hook }
		end
	end)
end

function M.subscribe(hook) -- TODO: generalize ptn matching to matching and registering mode
	if not hook.callback then error('missing callback in: ' .. tostring(hook)) end
	if M.debug_subscribe then print_debug('subscribe', hook) end
	hook = mk_hook(hook)
	hook.mode = tabled(hook.mode or modes)
	for _, e in ipairs(tabled(hook.event or error('missing event in: ' .. tostring(hook)))) do
		local ev_hooks = M._hooks[e]
		if not ev_hooks then
			ev_hooks = {}
			M._hooks[e] = ev_hooks
		end

		for _, m in ipairs(hook.mode) do
			local m_hooks = ev_hooks[m]
			if not m_hooks then
				m_hooks = {}
				ev_hooks[m] = m_hooks
			end

			m_hooks[hook] = hook
		end
		M.trigger { event = 'Subscribed', mode = hook.mode, match = e, data = hook }
	end

	return hook
end

swayimg.on_initialized(function()
	-- an error occured during config loading so we don't want to change the message
	if not swi then return print 'error - swi not initialized during on_initialized' end
	swi.initialized = true
	M.trigger { event = 'SwiEnter' }

	if M._hooks.SwiEnter then
		M._hooks.SwiEnter = nil

		-- easteregg
		local p = io.popen 'date +%d%m' or {}
		local o = p:read '*a'
		p:close()
		if o == '1003\n' then print [[Naughty, naughty! Didn't clean those hookers today...]] end
	end

	M.subscribe {
		event = 'Subscribed',
		pattern = 'SwiEnter',
		-- ensure all hooks expecting initialization get loaded
		-- (especially the lazy ones not checking swi.initialized)
		callback = function(h)
			h.data.callback()
			M._hooks.SwiEnter = nil
		end,
	}
end)

return M
