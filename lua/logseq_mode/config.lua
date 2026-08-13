local M = {}

M.defaults = {
	logseq_dir = vim.fn.expand("~/logseq-graph"),
	-- Optional: List of additional directories to include in unified search
	additional_dirs = {},
	-- Amount of extra space between lines (only works in GUI clients)
	linespace = 4,
	-- Task marker cycle. Last entry is treated as the "closed" state
	-- (excluded from :LogseqTodos and :LogseqAgenda).
	markers = { "TODO", "DOING", "DONE" },
	-- Default window for :LogseqAgenda, in days
	agenda_days = 14,
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
	-- Ensure paths are expanded (e.g. handle ~)
	if M.options.logseq_dir then
		M.options.logseq_dir = vim.fn.expand(M.options.logseq_dir)
	end
	if M.options.additional_dirs then
		local expanded = {}
		for _, dir in ipairs(M.options.additional_dirs) do
			table.insert(expanded, vim.fn.expand(dir))
		end
		M.options.additional_dirs = expanded
	end
end

return M
