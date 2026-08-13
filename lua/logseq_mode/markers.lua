local Config = require("logseq_mode.config")

local M = {}

-- Split a bullet line into indent, marker (may be nil) and the remaining text
function M.parse(line)
	local indent, body = line:match("^(%s*)%-%s*(.*)$")
	if not indent then
		return nil
	end
	for _, marker in ipairs(Config.options.markers or {}) do
		local pat = vim.pesc(marker)
		if body == marker then
			return indent, marker, ""
		end
		local rest = body:match("^" .. pat .. "%s+(.*)$")
		if rest then
			return indent, marker, rest
		end
	end
	return indent, nil, body
end

local function render(indent, marker, text)
	if marker then
		return indent .. "- " .. marker .. (text == "" and " " or " " .. text)
	end
	return indent .. "- " .. text
end

-- Replace the marker on the current line, keeping the cursor over the same text
local function set_marker(marker)
	local line = vim.api.nvim_get_current_line()
	local indent, current, text = M.parse(line)
	if not indent then
		vim.notify("Not on a bullet line", vim.log.levels.WARN)
		return
	end
	local new_line = render(indent, marker, text)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	vim.api.nvim_set_current_line(new_line)
	local shift = #new_line - #line
	vim.api.nvim_win_set_cursor(0, { row, math.max(0, col + shift) })
	return current, marker
end

-- TODO -> DOING -> DONE -> no marker -> TODO ...
function M.cycle(backwards)
	local markers = Config.options.markers or {}
	if #markers == 0 then
		return
	end
	local _, current = M.parse(vim.api.nvim_get_current_line())
	local index = nil
	for i, marker in ipairs(markers) do
		if marker == current then
			index = i
			break
		end
	end

	local next_marker
	if backwards then
		if index == nil then
			next_marker = markers[#markers]
		elseif index == 1 then
			next_marker = nil
		else
			next_marker = markers[index - 1]
		end
	else
		if index == nil then
			next_marker = markers[1]
		elseif index == #markers then
			next_marker = nil
		else
			next_marker = markers[index + 1]
		end
	end

	set_marker(next_marker)
end

-- Jump straight to the last marker in the cycle (usually DONE), or clear it
function M.toggle_done()
	local markers = Config.options.markers or {}
	local done = markers[#markers]
	if not done then
		return
	end
	local _, current = M.parse(vim.api.nvim_get_current_line())
	set_marker(current == done and markers[1] or done)
end

function M.remove()
	set_marker(nil)
end

return M
