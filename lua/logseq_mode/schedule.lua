local Config = require("logseq_mode.config")
local Markers = require("logseq_mode.markers")

local M = {}

local WEEKDAYS = {
	sun = 1,
	sunday = 1,
	mon = 2,
	monday = 2,
	tue = 3,
	tues = 3,
	tuesday = 3,
	wed = 4,
	wednesday = 4,
	thu = 5,
	thur = 5,
	thurs = 5,
	thursday = 5,
	fri = 6,
	friday = 6,
	sat = 7,
	saturday = 7,
}

local DAY = 24 * 60 * 60

-- Noon avoids DST edges shifting a date by a day
local function midday(year, month, day)
	return os.time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 })
end

local function today()
	local t = os.date("*t")
	return midday(t.year, t.month, t.day)
end

local function add_months(ts, months)
	local t = os.date("*t", ts)
	return midday(t.year, t.month + months, t.day)
end

--- Parse a date spec into a timestamp.
--- Accepts: "" / "today", "tomorrow", "yesterday", "+3d", "-2w", "+1m", "+1y",
--- weekday names ("fri", "friday" -> next occurrence, today included),
--- "YYYY-MM-DD", "YYYY/MM/DD", "MM-DD" (next occurrence).
---@return number|nil timestamp, string|nil err
function M.parse_date(spec)
	spec = vim.trim(spec or ""):lower()

	if spec == "" or spec == "today" then
		return today()
	end
	if spec == "tomorrow" then
		return today() + DAY
	end
	if spec == "yesterday" then
		return today() - DAY
	end

	local sign, count, unit = spec:match("^([%+%-])(%d+)([dwmy])$")
	if sign then
		local n = tonumber(count) * (sign == "-" and -1 or 1)
		if unit == "d" then
			return today() + n * DAY
		elseif unit == "w" then
			return today() + n * 7 * DAY
		elseif unit == "m" then
			return add_months(today(), n)
		else
			return add_months(today(), n * 12)
		end
	end

	local wday = WEEKDAYS[spec]
	if wday then
		local ts = today()
		for _ = 0, 6 do
			if tonumber(os.date("%w", ts)) + 1 == wday then
				return ts
			end
			ts = ts + DAY
		end
	end

	local y, m, d = spec:match("^(%d%d%d%d)[-/](%d%d?)[-/](%d%d?)$")
	if y then
		return midday(tonumber(y), tonumber(m), tonumber(d))
	end

	m, d = spec:match("^(%d%d?)[-/](%d%d?)$")
	if m then
		local t = os.date("*t")
		local ts = midday(t.year, tonumber(m), tonumber(d))
		if ts < today() then
			ts = midday(t.year + 1, tonumber(m), tonumber(d))
		end
		return ts
	end

	return nil, "Unrecognized date: " .. spec
end

function M.format_date(ts)
	return os.date("%Y-%m-%d %a", ts)
end

function M.is_property_line(line)
	if line:match("^%s*%-%s") or not line:match("%S") then
		return false
	end
	return line:match("^%s*SCHEDULED:") ~= nil
		or line:match("^%s*DEADLINE:") ~= nil
		or line:match("^%s*[%w_%-]+::") ~= nil
end

-- Walk up from the cursor to the bullet this line belongs to
local function current_bullet_row()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	for r = row, 1, -1 do
		if lines[r] and lines[r]:match("^%s*%-%s") then
			return r, lines
		end
	end
	return nil, lines
end

--- Insert (or replace) a SCHEDULED:/DEADLINE: line under the current bullet.
---@param kind string "SCHEDULED" or "DEADLINE"
---@param spec string date spec, optionally followed by a Logseq repeater (e.g. "+3d ++1w")
function M.stamp(kind, spec)
	local date_spec, repeater = (spec or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local ts, err = M.parse_date(date_spec)
	if not ts then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local row, lines = current_bullet_row()
	if not row then
		vim.notify("No bullet above the cursor to " .. kind:lower(), vim.log.levels.WARN)
		return
	end

	local indent = lines[row]:match("^(%s*)")
	local stamp = string.format(
		"%s  %s: <%s%s>",
		indent,
		kind,
		M.format_date(ts),
		(repeater ~= "" and " " .. repeater or "")
	)

	-- Find the property block that follows the bullet
	local last = row
	local existing = nil
	for r = row + 1, #lines do
		if not M.is_property_line(lines[r]) then
			break
		end
		if lines[r]:match("^%s*" .. kind .. ":") then
			existing = r
		end
		last = r
	end

	if existing then
		vim.api.nvim_buf_set_lines(0, existing - 1, existing, false, { stamp })
	else
		vim.api.nvim_buf_set_lines(0, last, last, false, { stamp })
	end
end

local function graph_dirs()
	local dirs = { Config.options.logseq_dir }
	for _, dir in ipairs(Config.options.additional_dirs or {}) do
		table.insert(dirs, dir)
	end
	return dirs
end

-- Every markdown file in the graph (and any additional dirs)
local function markdown_files()
	local files = {}
	for _, dir in ipairs(graph_dirs()) do
		if vim.fn.isdirectory(dir) == 1 then
			for _, file in ipairs(vim.fn.globpath(dir, "**/*.md", false, true)) do
				table.insert(files, file)
			end
		end
	end
	return files
end

local function open_markers()
	local markers = Config.options.markers or {}
	local open = {}
	for i, marker in ipairs(markers) do
		if i < #markers then -- last marker in the cycle is the "closed" one
			table.insert(open, marker)
		end
	end
	return open
end

local function block_text(lines, row)
	for r = row, 1, -1 do
		if lines[r]:match("^%s*%-%s") then
			return vim.trim(lines[r]:gsub("^%s*%-%s*", ""))
		end
	end
	return vim.trim(lines[row])
end

local function set_qflist(items, title)
	if #items == 0 then
		vim.notify("Nothing found: " .. title, vim.log.levels.INFO)
		return
	end
	vim.fn.setqflist({}, "r", { title = title, items = items })
	vim.cmd("copen")
end

--- Collect SCHEDULED:/DEADLINE: entries due within `days` (overdue always included).
function M.agenda(days)
	days = days or Config.options.agenda_days or 14
	local cutoff = today() + days * DAY
	local now = today()
	local items = {}

	for _, file in ipairs(markdown_files()) do
		local ok, lines = pcall(vim.fn.readfile, file)
		if ok then
			for row, line in ipairs(lines) do
				local kind, y, m, d = line:match("(SCHEDULED):%s*<(%d%d%d%d)-(%d%d)-(%d%d)")
				if not kind then
					kind, y, m, d = line:match("(DEADLINE):%s*<(%d%d%d%d)-(%d%d)-(%d%d)")
				end
				if kind then
					local ts = midday(tonumber(y), tonumber(m), tonumber(d))
					local text = block_text(lines, row)
					local _, marker = Markers.parse("- " .. text)
					local closed = marker and marker == (Config.options.markers or {})[#(Config.options.markers or {})]
					if ts <= cutoff and not closed then
						local label
						if ts < now then
							label = "OVERDUE"
						elseif ts == now then
							label = "TODAY"
						else
							label = string.format("in %dd", math.floor((ts - now) / DAY + 0.5))
						end
						table.insert(items, {
							filename = file,
							lnum = row,
							text = string.format("%s <%s> %s | %s", kind, M.format_date(ts), label, text),
							_ts = ts,
						})
					end
				end
			end
		end
	end

	table.sort(items, function(a, b)
		return a._ts < b._ts
	end)
	for _, item in ipairs(items) do
		item._ts = nil
	end
	set_qflist(items, string.format("Logseq Agenda (next %d days)", days))
end

--- Collect every open marker block (TODO/DOING/... but not the closed marker).
function M.todos()
	local markers = open_markers()
	if #markers == 0 then
		vim.notify("No markers configured", vim.log.levels.WARN)
		return
	end
	local items = {}
	for _, file in ipairs(markdown_files()) do
		local ok, lines = pcall(vim.fn.readfile, file)
		if ok then
			for row, line in ipairs(lines) do
				local _, marker, text = Markers.parse(line)
				if marker and vim.tbl_contains(markers, marker) then
					table.insert(items, {
						filename = file,
						lnum = row,
						col = #line:match("^%s*") + 3,
						text = marker .. " | " .. text,
					})
				end
			end
		end
	end
	set_qflist(items, "Logseq Todos (" .. table.concat(markers, "/") .. ")")
end

return M
