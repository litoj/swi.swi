---@module 'swi.utils'
local M = {}

---@generic O
---@param loader fun():`O`
---@return O
function M.lazy(loader)
	return setmetatable({}, {
		__index = function(self, idx)
			for k, v in pairs(loader()) do
				self[k] = v
			end
			return rawget(self, idx)
		end,
	})
end

function M.tabled(x) return type(x) == 'table' and x or { x } end
function M.rev_idx(t)
	local r = {}
	for k, v in pairs(t) do
		r[v] = k
	end
	return r
end

---@generic O: table
---@param t `O`
---@return O t copy
function M.soft_copy(t)
	local ret = {}
	for k, v in pairs(t) do
		ret[k] = v
	end
	return ret
end

---Nicely format the requested value to human readable rational numbers.
---@param img_meta table<string,string> the `.meta` field of the image
---@param tag string name/path of the exif value to get
--- single-word tags resolve to `Exif.Photo.<>`  or `Exif.Image.<>`
---@return string?
function M.format_exif(img_meta, tag)
	if not img_meta then return end

	if tag and tag:find('.', 0, true) then
		tag = img_meta[tag]
	else
		tag = img_meta['Exif.Photo.' .. tag] or img_meta['Exif.Image.' .. tag]
	end
	if not tag then return end

	local a, b = tag:match '^(%-?[0-9]+)/([0-9]+)$'
	if a then
		local x, y = tonumber(a), tonumber(b)
		local n = x / y
		if math.floor(n) == n then -- integer, not rational number -> done
			return '' .. n
		elseif n < 1 and (a:match '^10*$' or b:match '^10*$') then -- decimal point offset through the other side
			return ('1/%d'):format(y / x)
		else
			return '' .. n
		end
	end

	return tag
end

---A list of translations of vim-like+key-emmited symbols back to their names
M.key_map = {
	BS = 'BackSpace',
	Del = 'Delete',
	Esc = 'Escape',
	CR = 'Return',
	Enter = 'Return',
	PgUp = 'Prior',
	PgDown = 'Next',
	PageUp = 'Prior',
	PageDown = 'Next',
	['`'] = 'grave',
	['~'] = 'asciitilde',
	[' '] = 'Space',
	['-'] = 'minus',
	['_'] = 'underscore',
	['='] = 'equal',
	['+'] = 'plus',
	[','] = 'comma',
	['.'] = 'period',
}
for _, v in ipairs { 'Middle', 'Left', 'Right' } do
	M.key_map[v:sub(1, 1) .. 'MB'] = 'Mouse' .. v
	M.key_map[v .. 'Mouse'] = 'Mouse' .. v
end
for _, v in ipairs { 'Left', 'Right', 'Up', 'Down' } do
	M.key_map['SM' .. v:sub(1, 1)] = 'Scroll' .. v
	M.key_map[v:sub(1, 1) .. 'MS'] = 'Scroll' .. v
end

---Parse vim-like shortcuts into classic gui-style.
---@param bind string
---@return string
function M.transform_key(bind)
	if bind:match '^<.+>$' then bind = bind:sub(2, -2) end
	bind = bind:gsub('[AM][+-]', 'Alt+', 1):gsub('S[+-]', 'Shift+', 1):gsub('C[+-]', 'Ctrl+', 1)

	if bind:match 'Shift%+Tab$' then
		bind = bind:gsub('Shift%+Tab$', 'Shift+ISO_Left_Tab')
	else
		local key = bind:match '[^+-]*.$'
		bind = bind:sub(1, -#key - 1) .. (M.key_map[key] or key)
	end
	return bind
end

M.rev_key_map = M.rev_idx(M.key_map)

function M.short_key_name(bind)
	bind = bind:gsub('Alt[+-]', 'A-'):gsub('Shift[+-]', 'S-'):gsub('Ctrl[+-]', 'C-')
	if bind:match 'ISO_Left_Tab$' then
		bind = bind:gsub('S-(.*)ISO_Left_Tab', '%1')
	else
		local key = bind:match '[^+-]*.$'
		local found = M.rev_key_map[key]
		bind = bind:sub(1, -#key - 1) .. (found or key)
		if found then return ('<%s>'):format(bind) end
	end
	if bind:match '-.' then bind = ('<%s>'):format(bind) end
	return bind
end

M.max_tbl_len = 80

---@param t table
---@param indent string?
function M.tbl_to_str(t, indent)
	indent = (indent or '') .. '  '
	local s = {}
	local space = M.max_tbl_len
	for k, v in pairs(t) do
		if type(v) == 'table' then
			v = M.tbl_to_str(v, indent)
		elseif type(v) == 'function' then
			v = 'fn()'
		elseif type(v) == 'string' then
			v = ('"%s"'):format(v)
		end

		if type(k) == 'table' then k = '[]' end

		s[#s + 1] = type(k) == 'string' and ('%s=%s'):format(k, tostring(v)) or tostring(v)
		space = space - #s[#s]
	end
	if space <= 0 then
		return ('{\n%s%s}'):format(indent, table.concat(s, ',\n' .. indent))
	else
		return #s == 0 and '{}' or ('{ %s }'):format(table.concat(s, ', '))
	end
end

---Original tostring method
M.ts = tostring

function M.to_pretty_str(x)
	if type(x) == 'table' then return M.tbl_to_str(x, '') end
	if type(x) == 'number' then
		if x > 0x00ffffff then return ('0x%x'):format(x) end
		if math.floor(x * 100) == x * 100 then return '' .. x end
		return ('%.5f'):format(x)
	end
	return M.ts(x)
end

_G.tostring = M.to_pretty_str

---@param action_match string luapat to match the last internal trace to trim
---@param stacktrace string use debug.traceback() to get the trace
function M.pretty_trace(action_match, stacktrace)
	return stacktrace
		:gsub(': in main chunk.*$', '') -- trim all calls past the main trace
		:gsub('^.-' .. action_match .. "'\n", '') -- trim interals up to traced fn
		:gsub('[^\n]+proxy[^\n]+\n', '') -- trim all proxy calls
		:gsub('[^\n<"]+/swayimg/', '') -- trim path to config dir
		:gsub('[ \t]*%./', '') -- trim path to config dir
		:gsub("in function '*([^%s']+)'?", '%1()') -- format as a fn call
		-- :gsub('\n%s+%[C%][^\n]+', '') -- trim [C] calls
		:gsub('\n(%S)', '\n\t%1') -- indent continuing lines
end

---@param path string
---@return false? false if operation failed due to incomplete path
function M.set_var_by_path(path, new)
	local val = _G
	for key in path:gmatch '([^.]+)%.' do
		if val == nil then return false end
		val = val[key]
	end
	val[path:match '[^.]+$'] = new
end

---@param ptn string|string[]? event pattern to specify which exact options to watch for
---@return fun():table<string,any> reclaimer call it to finish collection of option changes
function M.capture_opt_changes(ptn)
	local t = {}
	local hook_id = e.subscribe {
		event = 'OptionSet',
		pattern = ptn,
		---@diagnostic disable-next-line: undefined-field
		callback = function(ev) t[ev.match] = { old = ev.old_data, new = ev.data } end,
	}
	return function()
		e.unsubscribe { event = 'OptionSet', id = hook_id }
		return t
	end
end

return M
