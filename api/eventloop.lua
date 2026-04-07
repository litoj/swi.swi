---@module 'swi.api.eventloop'

local U = require 'swi.utils'
local tabled = U.tabled

---@private
---@class swi.eventloop.hook: swi.eventloop.subscribe.opts
---@field pattern table<string|integer,string>
---@field mode string[]

---@class swi.api.eventloop: swi.eventloop
local M = {
	---@type {[event_name_t]:{[string]:swi.eventloop.hook[]}}
	_hooks = {},
	debug_trigger = false,
	debug_subscribe = false,
} -- TODO: could improve deleting perf by having a {[hook_id]:counter}

local modes = { 'viewer', 'gallery', 'slideshow' }
local rev_modes = U.rev_idx(modes)

local function print_debug(name, t)
	if t.event == 'Subscribed' and name == 'trigger' then return end
	local tbl = { event = t.event, mode = t.mode, match = t.match or t.pattern, data = t.data }
	print(U.pretty_trace(name, debug.traceback()), name, U.tbl_to_str(tbl, ''))
end

---@param cfg swi.eventloop.subscribe.opts
---@return swi.eventloop.hook
local function mk_hook(cfg)
	---@diagnostic disable-next-line: undefined-field .match field used as help for common misconfig
	local t = tabled(cfg.pattern or cfg.match or { '^' })
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
	cfg.mode = cfg.mode and U.rev_idx(tabled(cfg.mode)) or rev_modes
	return cfg
end

function M.subscribe(hook)
	if not hook.callback then error('missing callback in: ' .. tostring(hook)) end
	if M.debug_subscribe then print_debug('subscribe', hook) end
	hook = mk_hook(hook)
	for _, e in ipairs(tabled(hook.event or error('missing event in: ' .. tostring(hook)))) do
		local ev_hooks = M._hooks[e]
		if not ev_hooks then
			ev_hooks = {}
			M._hooks[e] = ev_hooks
		end

		for k, v in pairs(hook.pattern) do
			if v then
				k = type(k) == 'string' and k or '*'
				local hooks = ev_hooks[k]
				if not hooks then
					hooks = {}
					ev_hooks[k] = hooks
				end
				hooks[#hooks + 1] = hook
			end
		end

		M.trigger { event = 'Subscribed', mode = hook.mode, match = e, data = hook }
	end

	return hook
end

---@param ptn_map {[string]:swi.eventloop.hook[]}
---@return fun():(hook:swi.eventloop.hook?,ptn:string,i:integer)
local function matcher(match, ptn_map)
	return coroutine.wrap(function()
		if not match then
			for ptn, hooks in pairs(ptn_map) do
				for i, h in pairs(hooks) do
					coroutine.yield(h, ptn, i)
				end
			end
			return
		end

		local hooks = ptn_map[match]
		if hooks then
			for i, h in pairs(hooks) do
				coroutine.yield(h, match, i)
			end
		end

		hooks = ptn_map['*']
		if hooks then
			for i, h in ipairs(hooks) do
				if h.pattern[match] == nil then -- `true` was already processed, `false` is to skip it
					for _, ptn in ipairs(h.pattern) do
						if match:match(ptn) then
							coroutine.yield(h, '*', i)
							break
						end
					end
				end
			end
		end
	end)
end

---@alias swi.eventloop.applicator fun(h:swi.eventloop.hook,ev:event_name_t, pnt:string,i:integer)

---@param f swi.eventloop.filter.opts
---@param on_match swi.eventloop.applicator
function M.apply_filtered(f, on_match)
	---@type (fun(h:swi.eventloop.hook):boolean?)[]
	local checks = {}
	if f.id then checks[#checks + 1] = function(h) return f.id == h end end
	if f.group then checks[#checks + 1] = function(h) return f.group == h.group end end
	if f.mode then
		f.mode = tabled(f.mode)
		checks[#checks + 1] = function(h)
			if not h.mode then return true end
			for _, m in ipairs(modes) do
				if h.mode[m] then return true end
			end
		end
	end

	for _, ev in pairs(tabled(f.event or U.rev_idx(M._hooks))) do
		local ev_hooks = M._hooks[ev]
		if ev_hooks then
			for hook, ptn, i in matcher(f.match, ev_hooks) do
				local ok = true
				for _, check in ipairs(checks) do
					if not check(hook) then
						ok = false
						break
					end
				end
				if ok then on_match(hook, ev, ptn, i) end
			end
		end
	end
end

function M.unsubscribe(f)
	M.apply_filtered(f, function(hook, ev, ptn, i)
		local ev_hooks = M._hooks[ev]
		local ptn_hooks = ev_hooks[ptn]

		ptn_hooks[i] = nil
		if not next(ptn_hooks) then
			ev_hooks[ptn] = nil
			if not next(ev_hooks) then M._hooks[ev] = nil end
		end
	end)
end

function M.get_subscribed(f)
	local t = {}
	M.apply_filtered(f or {}, function(h) t[h] = h end)
	return t
end

function M.trigger(state)
	if M.debug_trigger then print_debug('trigger', state) end

	---@cast state swi.eventloop.filter.opts
	state.mode = state.mode or swayimg.get_mode()
	M.apply_filtered(state, function(hook)
		local ok, ret = xpcall(hook.callback, debug.traceback, state)
		if not ok then
			---@diagnostic disable-next-line: param-type-mismatch
			swayimg.text.set_status(string.gsub(ret, '\t', '  '))
			print(ret)
		elseif ret then
			M.unsubscribe { id = hook } -- unsub from all places, not just where it matched
		end
	end)
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
