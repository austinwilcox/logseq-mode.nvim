local Config = require("logseq_mode.config")
local Formatter = require("logseq_mode.formatter")
local Markers = require("logseq_mode.markers")
local Schedule = require("logseq_mode.schedule")

local M = {}

-- Helper to indent/unindent a tree
local function move_tree(direction)
	local start_line = vim.fn.line(".")
	local current_indent = vim.fn.indent(start_line)
	local last_line = vim.fn.line("$")
	local end_line = start_line

	-- Find the range of children
	for l = start_line + 1, last_line do
		local line_text = vim.fn.getline(l)
		-- Only check indent of non-empty lines
		if line_text:match("%S") then
			local next_indent = vim.fn.indent(l)
			if next_indent <= current_indent then
				break
			end
			end_line = l
		else
			-- Include empty lines in the block
			end_line = l
		end
	end

	-- Construct the range command (e.g., ":10,15>")
	local cmd_char = direction == "in" and ">" or "<"
	local cmd = string.format("%d,%d%s", start_line, end_line, cmd_char)

	-- Save cursor position to prevent jumping
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	vim.cmd(cmd)

	-- Restore cursor
	pcall(vim.api.nvim_win_set_cursor, 0, cursor_pos)
end

-- Helper for auto-bullet
local function get_bullet_prefix(line)
	line = line or vim.api.nvim_get_current_line()
	-- Match leading whitespace + bullet (with or without trailing space)
	local indent = line:match("^(%s*)%-%s")
	if not indent then
		-- Also treat a bare "-" (empty bullet) as a bullet line
		indent = line:match("^(%s*)%-$")
	end
	if indent then
		return indent .. "- "
	end
	return nil
end

-- Leading whitespace of the current line ('autoindent' is off in these buffers,
-- so new lines carry the indent explicitly)
local function get_indent_prefix()
	return vim.api.nvim_get_current_line():match("^(%s*)")
end

-- Drop one indent level from a bullet prefix (tab, or 2 spaces)
local function outdent_prefix(prefix)
	local indent = prefix:match("^(%s*)")
	if indent:sub(-1) == "\t" then
		return indent:sub(1, -2) .. "- "
	elseif indent:sub(-2) == "  " then
		return indent:sub(1, -3) .. "- "
	end
	return nil
end

--- Open a journal page. `spec` is any date spec understood by Schedule.parse_date
--- ("" = today, "+1d", "tomorrow", "fri", "2026-09-01", ...).
function M.daily_note(spec)
	local ts, err = Schedule.parse_date(spec)
	if not ts then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end
	local path = Config.options.logseq_dir .. "/journals/" .. os.date("%Y_%m_%d", ts) .. ".md"
	vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.unified_search()
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("Snacks.nvim is required for unified search", vim.log.levels.ERROR)
		return
	end

	local dirs = { Config.options.logseq_dir }
	if Config.options.additional_dirs then
		for _, dir in ipairs(Config.options.additional_dirs) do
			table.insert(dirs, dir)
		end
	end

	snacks.picker.grep({
		dirs = dirs,
		title = "Unified Search",
	})
end

function M.hoist_block()
	-- 1. Move cursor to first non-blank character
	vim.cmd("normal! ^")
	-- 2. Scroll so current line is at the top
	vim.cmd("normal! zt")
	-- 3. Scroll horizontally so current cursor is at the left
	vim.cmd("normal! zs")
end

function M.setup(opts)
	Config.setup(opts)

	-- Register User Commands
	vim.api.nvim_create_user_command("LogseqDaily", function(cmd)
		M.daily_note(cmd.args)
	end, { nargs = "?", desc = "Open a journal page (date spec: +1d, tomorrow, fri, 2026-09-01)" })
	vim.api.nvim_create_user_command("LogseqSchedule", function(cmd)
		Schedule.stamp("SCHEDULED", cmd.args)
	end, { nargs = "*", desc = "Add SCHEDULED: <date> to the current block" })
	vim.api.nvim_create_user_command("LogseqDeadline", function(cmd)
		Schedule.stamp("DEADLINE", cmd.args)
	end, { nargs = "*", desc = "Add DEADLINE: <date> to the current block" })
	vim.api.nvim_create_user_command("LogseqAgenda", function(cmd)
		Schedule.agenda(tonumber(cmd.args))
	end, { nargs = "?", desc = "Quickfix list of upcoming/overdue scheduled blocks" })
	vim.api.nvim_create_user_command("LogseqTodos", function()
		Schedule.todos()
	end, { desc = "Quickfix list of open marker blocks" })

	-- Register Formatter if Conform is loaded
	local has_conform, conform = pcall(require, "conform")
	if has_conform then
		conform.formatters.logseq_fixer = Formatter.get_config(Config.options.logseq_dir)
	end

	-- FileType Autocommand
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "markdown",
		callback = function(ev)
			-- Don't run on special buffers (nofile, prompt, etc.)
			if not vim.api.nvim_buf_is_valid(ev.buf) or vim.bo[ev.buf].buftype ~= "" then
				return
			end

			local bufname = ev.file
			local logseq_dir = Config.options.logseq_dir

			if not logseq_dir or type(logseq_dir) ~= "string" or not bufname or bufname == "" then
				return
			end

			if bufname:find(logseq_dir, 1, true) then
				-- Set local options
				vim.opt_local.foldmethod = "indent"
				vim.opt_local.shiftwidth = 0 -- Use tabstop
				vim.opt_local.tabstop = 2 -- Or whatever Logseq prefers
				vim.opt_local.expandtab = false -- Logseq uses real tabs
				vim.opt_local.wrap = true
				vim.opt_local.breakindent = true
				vim.opt_local.breakindentopt = "shift:2"
				vim.opt_local.scrolloff = 0

				-- Bullet continuation supplies its own indent, so keep Vim from
				-- adding one too (an extra auto-indent would double the leading tabs).
				vim.opt_local.autoindent = false
				vim.opt_local.smartindent = false
				vim.opt_local.cindent = false
				vim.opt_local.indentexpr = ""
				-- Don't let 'comments' auto-insert "- " on top of ours
				vim.opt_local.formatoptions:remove("r")
				vim.opt_local.formatoptions:remove("o")

				-- Keymaps
				local map = function(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc, silent = true })
				end
				local map_expr = function(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc, expr = true, silent = true })
				end

				-- Smart Indent/Unindent
				map("n", "<Tab>", function()
					move_tree("in")
				end, "Smart Logseq Indent")
				map("n", "<S-Tab>", function()
					move_tree("out")
				end, "Smart Logseq Unindent")

				-- Auto-continuation: Enter
				map_expr("i", "<CR>", function()
					local prefix = get_bullet_prefix()
					if not prefix then
						return "<CR>" .. get_indent_prefix()
					end
					local line = vim.api.nvim_get_current_line()
					-- Empty bullet: outdent it, or drop the bullet at top level
					if line:match("^%s*%-%s*$") then
						local outdented = outdent_prefix(prefix)
						if outdented then
							return "<Esc>cc" .. outdented
						end
						return "<Esc>cc"
					end
					-- 'autoindent' is off in these buffers, so the prefix carries the indent
					return "<CR>" .. prefix
				end, "Logseq List Continuation")

				-- Auto-continuation: o (keeps SCHEDULED:/DEADLINE: lines attached to their block)
				map_expr("n", "o", function()
					local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
					local row = vim.api.nvim_win_get_cursor(0)[1]
					local bullet
					for r = row, 1, -1 do
						if lines[r]:match("^%s*%-%s") then
							bullet = r
							break
						end
					end
					if not bullet then
						return "o" .. get_indent_prefix()
					end
					-- Step past the block's property lines so the new bullet lands after them
					local target = bullet
					while lines[target + 1] and Schedule.is_property_line(lines[target + 1]) do
						target = target + 1
					end
					local down = math.max(0, target - row)
					return string.rep("j", down) .. "o" .. get_bullet_prefix(lines[bullet])
				end, "Logseq New Line Below")

				-- Auto-continuation: O
				map_expr("n", "O", function()
					return "O" .. (get_bullet_prefix() or get_indent_prefix())
				end, "Logseq New Line Above")

				-- Task markers
				map("n", "<leader>zt", function()
					Markers.cycle(false)
				end, "Logseq Cycle Marker")
				map("n", "<leader>zT", function()
					Markers.cycle(true)
				end, "Logseq Cycle Marker Backwards")
				map("n", "<leader>zx", Markers.toggle_done, "Logseq Toggle Done")

				-- Scheduling
				map("n", "<leader>zs", function()
					vim.ui.input({ prompt = "SCHEDULED (e.g. +3d, fri, 2026-09-01): " }, function(input)
						if input then
							Schedule.stamp("SCHEDULED", input)
						end
					end)
				end, "Logseq Schedule Block")
				map("n", "<leader>zd", function()
					vim.ui.input({ prompt = "DEADLINE (e.g. +3d, fri, 2026-09-01): " }, function(input)
						if input then
							Schedule.stamp("DEADLINE", input)
						end
					end)
				end, "Logseq Deadline Block")

				-- Hoisting
				map("n", "<leader>zl", M.hoist_block, "Logseq Hoist Block")
			end
		end,
	})

	-- Dynamic Line Spacing (GUI only)
	M.default_linespace = vim.opt.linespace:get() or 0
	vim.api.nvim_create_autocmd("BufEnter", {
		callback = function(ev)
			-- Don't run on special buffers
			if not vim.api.nvim_buf_is_valid(ev.buf) or vim.bo[ev.buf].buftype ~= "" then
				return
			end

			local bufname = ev.file
			local logseq_dir = Config.options.logseq_dir

			if not logseq_dir or type(logseq_dir) ~= "string" or not bufname or bufname == "" then
				return
			end

			-- Check if current buffer is in logseq dir
			if bufname:find(logseq_dir, 1, true) then
				if Config.options.linespace and Config.options.linespace > 0 then
					vim.opt.linespace = Config.options.linespace
				end
			else
				-- Restore default
				if M.default_linespace then
					vim.opt.linespace = M.default_linespace
				end
			end
		end,
	})
end

return M

