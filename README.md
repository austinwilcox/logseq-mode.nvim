# logseq-mode.nvim

A Neovim plugin for editing [Logseq](https://logseq.com/) graphs.

It provides:
- **Smart Indentation**: `<Tab>` and `<S-Tab>` move the entire bullet tree (parent + children).
- **Auto-bullet**: `<CR>`, `o`, and `O` automatically continue the bullet list.
- **Strict Formatting**: An `awk`-based formatter (via `conform.nvim`) that cleans up `collapsed::true` and enforces hierarchy/indentation levels compatible with Logseq.
- **Task Markers**: Cycle `TODO` → `DOING` → `DONE` → none on the current block, Logseq-style.
- **Scheduling**: `SCHEDULED:`/`DEADLINE:` stamps with relative dates (`+3d`, `fri`, `2026-09-01`), plus an agenda list.
- **Daily Note Access**: `:LogseqDaily` (today, or any date spec) or Lua API.
- **Hoisting**: Focus on the current block (`<leader>zl`).

## Installation

### using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Conor-McLeod/logseq-mode.nvim", 
  dir = "/path/to/logseq-mode.nvim", -- If local
  dependencies = {
    "stevearc/conform.nvim", -- Optional, for formatting
    "folke/snacks.nvim",     -- Optional, for grep picker
  },
  opts = {
    logseq_dir = "~/logseq-graph", -- Path to your graph
    additional_dirs = { "~/main-vault" }, -- Optional, for unified search
    markers = { "TODO", "DOING", "DONE" }, -- Marker cycle; last entry = "closed"
    agenda_days = 14, -- Default window for :LogseqAgenda
  },
  config = function(_, opts)
    require("logseq_mode").setup(opts)
  end,
}
```

## Configuration

### Formatters (Conform.nvim)

To enable the fix-formatting on save, you need to configure `conform.nvim` to use the `logseq_fixer`.

```lua
{
  "stevearc/conform.nvim",
  opts = function(_, opts)
    opts.formatters_by_ft = opts.formatters_by_ft or {}
    
    -- Add logseq_fixer to markdown
    -- It only runs if the file is inside the configured logseq_dir
    if not opts.formatters_by_ft.markdown then
      opts.formatters_by_ft.markdown = { "logseq_fixer" }
    else
      table.insert(opts.formatters_by_ft.markdown, "logseq_fixer")
    end
  end,
}
```

### Keymaps

The plugin automatically sets buffer-local keymaps for Markdown files inside your `logseq_dir`.

| Key | Description |
| --- | --- |
| `<Tab>` | Indent current tree (Smart Indent) |
| `<S-Tab>` | Unindent current tree |
| `<CR>` (Insert) | Continue list (auto-bullet) |
| `o` / `O` | New line with bullet (`o` steps past `SCHEDULED:`/`DEADLINE:` lines) |
| `<leader>zt` / `<leader>zT` | Cycle task marker forward / backward |
| `<leader>zx` | Toggle the closed marker (`DONE`) |
| `<leader>zs` | Prompt for a `SCHEDULED:` date |
| `<leader>zd` | Prompt for a `DEADLINE:` date |
| `<leader>zl` | Hoist block (Focus) |

### Commands

| Command | Description |
| --- | --- |
| `:LogseqDaily [date]` | Open a journal page — today by default, or `+1d`, `tomorrow`, `fri`, `2026-09-01` |
| `:LogseqSchedule <date> [repeater]` | Add/replace `SCHEDULED: <date>` on the current block, e.g. `:LogseqSchedule +3d ++1w` |
| `:LogseqDeadline <date> [repeater]` | Same, for `DEADLINE:` |
| `:LogseqAgenda [days]` | Quickfix list of scheduled/deadline blocks due within `days` (overdue always shown, closed markers skipped) |
| `:LogseqTodos` | Quickfix list of every open marker block in the graph |

```vim
:LogseqDaily                  " today's journal
:LogseqDaily +1d              " tomorrow's journal (created on write)
:LogseqDaily 2026-09-01

:LogseqSchedule               " SCHEDULED: <today>
:LogseqSchedule +3d           " three days out
:LogseqSchedule fri           " next Friday (today counts)
:LogseqSchedule mon ++1w      " next Monday, repeating weekly
:LogseqDeadline 2026-09-01

:LogseqAgenda                 " overdue + next 14 days
:LogseqAgenda 3               " overdue + next 3 days
:LogseqTodos                  " every TODO/DOING block in the graph
```

Both stamp commands act on the bullet at or above the cursor, so they also work with the cursor
parked on an existing `SCHEDULED:`/`id::` line. Running the same kind twice replaces the stamp
instead of stacking a second one.

### Task markers

Markers live inline on the bullet, the way Logseq stores them:

```markdown
- TODO write report
  SCHEDULED: <2026-08-16 Sun>
	- DOING draft intro
	- DONE outline
```

`<CR>` deliberately does *not* copy the marker onto the next block — same as Logseq, a new block starts plain.

Accepted date specs: `today`, `tomorrow`, `yesterday`, `+3d` / `-2w` / `+1m` / `+1y`, weekday names
(`fri`, `monday` — next occurrence, today included), `2026-09-01`, and `09-01` (next occurrence).
A trailing Logseq repeater is passed through verbatim: `:LogseqSchedule mon ++1w` → `SCHEDULED: <2026-08-17 Mon ++1w>`.

### Marker highlighting with todo-comments.nvim

[folke/todo-comments.nvim](https://github.com/folke/todo-comments.nvim) highlights keywords in *comments*
followed by a colon, so Logseq markers (`- TODO buy milk`) need two tweaks: extra keywords, and a
second pattern that matches a marker right after a bullet.

```lua
{
  "folke/todo-comments.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    keywords = {
      DOING = { icon = " ", color = "warning", alt = { "NOW" } },
      LATER = { icon = " ", color = "hint" },
      DONE = { icon = " ", color = "hint", alt = { "CANCELED", "CANCELLED" } },
    },
    highlight = {
      -- Logseq markers are not comments, so treesitter's comment check has to go
      comments_only = false,
      pattern = {
        [[.*<(KEYWORDS)\s*:]], -- the default: code comments (TODO:)
        [[^\s*- (KEYWORDS)>]], -- Logseq blocks (- TODO ...)
      },
    },
  },
}
```

`comments_only = false` is global. The patterns keep it tame: a keyword only highlights when it is
followed by a colon or sits directly after a `- ` bullet, so prose like `- a TODO in here` stays plain.

### API

```lua
local logseq = require("logseq_mode")

-- Open today's journal (or logseq.daily_note("+1d") for tomorrow)
logseq.daily_note()

-- Markers and scheduling
require("logseq_mode.markers").cycle()          -- TODO -> DOING -> DONE -> none
require("logseq_mode.markers").toggle_done()
require("logseq_mode.schedule").stamp("SCHEDULED", "+3d")
require("logseq_mode.schedule").agenda(7)
require("logseq_mode.schedule").todos()

-- Search across Logseq + other directories (requires snacks.nvim)
logseq.unified_search()
```
