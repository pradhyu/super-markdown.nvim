# 🚀 super-markdown.nvim

<div align="center">

**The premier, all-in-one Markdown powerhouse for Neovim.**

*High-fidelity in-buffer live rendering • Native terminal Mermaid diagram preview • High-speed Telescope & Snacks TOC search • Intelligent table formatting & authoring tools*

[![Neovim 0.10+](https://img.shields.io/badge/Neovim-0.10+-blueviolet.svg?style=flat-square&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%20%2F%20LuaJIT-blue.svg?style=flat-square&logo=lua)](https://www.lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](./LICENSE)

</div>

---

## 🌟 Why `super-markdown.nvim`?

Existing Neovim markdown plugins force you to compromise:
- **`render-markdown.nvim`** offers in-buffer rendering, but lacks Mermaid diagram rendering, Telescope TOC search, and table tools.
- **`markdown-preview.nvim`** renders Mermaid, but kicks you out of your editor into a heavy external browser window.
- **`markview.nvim`** can be sluggish on larger notes and breaks across Treesitter updates.
- **`image.nvim`** requires external C rocks, causing frequent crashes or scrolling artifacts.

**`super-markdown.nvim`** solves this by unifying the entire modern markdown experience into a single, cohesive, zero-friction pure-Lua plugin that runs natively in your terminal.

---

## ✨ Features

### 1. In-Buffer Live Rendering & Preview
Render Markdown elements directly inside your active buffer without losing your cursor or editing context:
- **Headings**: Styled level icons (`󰲡 `, `󰲣 `, `󰲥 `, `󰲧 `, `󰲩 `, `󰲫 `) with optional background banners.
- **Interactive Checkboxes**:
  - `[ ]` ➔ `󰄱 ` (Unchecked)
  - `[x]` ➔ `󰄵 ` (Checked, highlighted)
  - `[-]` ➔ `󰡖 ` (Canceled / Strikethrough)
  - `[/]` ➔ `󰄰 ` (In-progress)
  - `[!]` ➔ `󰀦 ` (Important)
  - `[?]` ➔ `󰋽 ` (Question)
  - Single-keystroke toggle or cycle with `<leader>mx`.
- **GitHub & Obsidian Callouts**: Styled admonition blocks with left vertical accent bar:
  - `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`, `> [!DANGER]`, `> [!TODO]`
- **Box-Drawing Tables**: Delimiter rows and pipes dynamically styled with clean Unicode box-drawing characters (`┌─┬─┐`, `│ │ │`, `├─┼─┤`, `└─┴─┘`).
- **Code Block Badges**: Top border banners with language icons (`󰢱 lua`, `󰌠 python`, `󰛦 rust`, `󰡷 mermaid`) and framed bottom borders.
- **Horizontal Dividers**: `---`, `***` replaced with elegant full-width divider lines.
- **Concealed Links**: URLs concealed while link text is styled with `󰌹 ` and underlined.

### 2. Mermaid Diagram Engine (Terminal Graphics & ASCII)
### 2. Automated In-Line Mermaid Diagram Engine
Write ```` ```mermaid ```` diagrams and have them **render automatically in line** directly inside the active buffer—no manual preview required:
- **Full Syntax Highlighting**: Real-time syntax highlighting for raw Mermaid text (keywords, directions, connectors/arrows, node shapes & brackets, pipe edge labels, comments, strings, styles, and hex colors) powered by live buffer extmarks and standard Vim syntax (`syntax/mermaid.vim`).
- **Live In-Buffer Rendering (`virt_lines`)**: Diagrams are parsed and rendered directly beneath the code block as clean, connected Unicode diagrams that scroll naturally with the buffer.
- **Full Diagram Type Support**: Flowcharts (TD, LR with shapes & edge labels), Sequence Diagrams (participants, lifelines, message arrows, step numbers, self-calls), and State Machines.
- **Terminal Graphics & Floating Preview (`<leader>mp`)**: Pixel-perfect Kitty Graphics Protocol rendering via `kitten icat` inside floating popup windows when high-resolution image preview is desired.
- **Instant SHA-256 Disk Caching**: Compiled diagrams are cached in `~/.cache/nvim/super_markdown/mermaid/`, making subsequent renders instantaneous (0ms).

### 3. High-Speed TOC Viewer with Telescope Search
- **Telescope Heading Finder (`<leader>mo`)**:
  - Hierarchical tree display with indented level icons in natural top-to-bottom document order.
  - Live fuzzy search across all document headings.
  - Contextual split previewer that automatically scrolls to and highlights the target heading in the preview window.
  - `<CR>` jumps to the heading and unfolds folds (`zv`).
- **Universal Fallback**: Automatically integrates with `Snacks.picker` or `vim.ui.select` if Telescope is not installed.
- **Document Outline Sidebar (`<leader>ms`)**:
  - Split outline sidebar displaying the document table of contents.
  - Live scrolling: moving up and down the sidebar automatically scrolls the markdown viewer to the highlighted section.
  - Pressing `<CR>` jumps to the selected heading and switches focus directly to the markdown viewer.

### 4. Automated Table Alignment & Authoring Tools
- **Automated In-Line Column Alignment**: Ragged or unaligned Markdown tables are automatically rendered with perfectly aligned columns, custom alignment indicators (`:---`, `:---:`, `---:`), and box-drawing borders without modifying the buffer text.
- **Source Formatter (`<leader>mtf`)**: Explicitly formats and snaps the buffer text itself into clean Markdown spacing.
- **Table Cell Navigation**: Press `<Tab>` to jump to the next cell and `<S-Tab>` to the previous cell. Pressing `<Tab>` on the last cell automatically adds a new row!
- **Smart List Continuation**: Pressing `<CR>` in insert mode automatically continues unordered (`- `, `* `, `+ `) and numbered (`1. `) lists.
- **Smart Link Follow & Paste (`<leader>ml` / `gx`)**: Open URLs in your browser or jump directly to local Markdown notes.

### 5. Hierarchical Heading Folding with Gutter Indicators
- **Gutter Fold Indicators (`+` and `-`)**:
  - Open folds display `-` in the fold column, closed folds display `+`, and nested lines display `│`.
- **Hierarchical Folds**:
  - H1 headings fold all subheadings down to the next H1; nested H2–H6 headings create structured sub-folds.
- **Stylized Fold Text**:
  - Closed folds render clean headings with level icons and line counts: ` 󰲡 Section Name  ⋯ (12 lines)`.
- **Fold All & Unfold All**:
  - Fold all sections at once via `:SuperMarkdown fold_all` or `<leader>mzM` (`zM`).
  - Unfold all sections at once via `:SuperMarkdown unfold_all` or `<leader>mzR` (`zR`).
  - Toggle individual section folds via `:SuperMarkdown fold_toggle` or `<leader>mza` (`za`).
  - Fold to specific depth via `:SuperMarkdown fold_level <N>`.

### 6. Spec-Driven Development (SDD) & LLM Workflow Suite
Built for modern developers who write, maintain, and navigate technical specifications to drive LLM code and test generation:
- **Live Heading Progress & Traceability Badges**:
  - Headings automatically display section task rollups (`󰄵 3/5`), blockers (`󰀦 1`), open questions (`󰋽 1`), and implementation/test badges (`󰅩 impl`, `󰙨 test`)—even when folded!
  - Document status headers (`> **Document Status**: APPROVED` or `status: DRAFT`) render semantic status badges and can be cycled with `<leader>msd` (`:SuperMarkdown spec_status`).
- **Spec Health & Traceability Dashboard (`<leader>mss` / `:SuperMarkdown spec_dashboard`)**:
  - Interactive floating HUD showing overall Spec Readiness Score (`0-100`), visual task completion bar, section rollups, open questions (`[?]`), blockers (`[!]`), verified `@impl`/`@test` file links, and clarity lint checks. Press `<CR>` on any item to jump straight to that line.
- **Semantic Spec Explorer (`<leader>msp` / `:SuperMarkdown spec_pick [filter]`)**:
  - Fuzzy-search across all open questions (`question`), blockers (`blocker`), requirements (`requirement`, e.g., `REQ-01`), tasks (`task`), Mermaid diagrams (`diagram`), tables (`table`), and code traceability references (`ref`).
- **Spec Linter for LLM Clarity (`<leader>msl` / `:SuperMarkdown spec_lint`)**:
  - Publishes Neovim diagnostics (`vim.diagnostic`) flagging vague/ambiguous specification language (*"should be fast"*, *"handle errors gracefully"*, *"etc."*, *"TBD"*), unresolved `[?]` questions, `[!]` blockers, and missing `@impl:` / `@test:` target files.
- **Spec Template Scaffolder (`<leader>msn` / `:SuperMarkdown spec_new [template]`)**:
  - Instant scaffolding for `architecture`, `feature`, `api`, and `test_plan` specs complete with Mermaid diagrams, requirement tables, and `@impl`/`@test` tags.
- **LLM Context Bundler & Prompt Studio (`<leader>my`, `<leader>mgc`, `<leader>mgt`, `<leader>mgr`)**:
  - **Context Bundle (`<leader>my`)**: Extracts the active spec section + breadcrumb hierarchy + **auto-inlined source/test files** referenced via `@impl:` / `@test:` / Markdown links into a `<spec_context>` bundle on your clipboard with token estimates.
  - **Generate Implementation Code (`<leader>mgc`)**: Opens the interactive **LLM Prompt Studio** with a structured implementation prompt for the active section. Edit in place, yank (`y`), or press `r` to dispatch directly to your CLI agent (`claude`, `gemini`, `llm`, `agy`).
  - **Generate Application Tests (`<leader>mgt`)**: Converts the section's acceptance criteria, requirement IDs (`REQ-*`), Mermaid branches, and edge-case tables into a comprehensive test generation prompt.
  - **Review & Co-Author Spec (`<leader>mgr`)**: Generates a critique prompt combining your spec section and any active lint warnings so the LLM can tighten edge cases, tables, and diagrams.
- **Smart Code Reference Jump & Floating Peek (`<leader>ml` & `<leader>mK`)**:
  - Jump to or peek inside `@impl: path/to/file.lua:42`, `[file](./path#L10-L25)`, inline `` `path/file.lua:10` ``, or `#heading-anchor` links in a floating preview window without leaving your spec.
- **Executable Spec Code Blocks (`<leader>mrun` / `:SuperMarkdown run_block`)**:
  - Execute `lua`, `bash`/`sh`, `python`, or `javascript` code blocks directly inside your spec and render live `󰄵 PASS` / `󰀦 FAIL` virtual lines beneath the block.

---

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "pradhyu/super-markdown.nvim",
  ft = { "markdown", "md", "markdown.mdx" },
  dependencies = {
    -- Optional: for high-resolution terminal image rendering
    -- Kitty, WezTerm, or Ghostty terminal recommended
    -- ImageMagick (`magick`) recommended for SVG->PNG conversion
  },
  opts = {
    render = {
      enabled = true,
    },
    mermaid = {
      theme = "dark", -- "dark", "default", "forest", "neutral"
    },
    toc = {
      picker = "auto", -- "auto", "telescope", "snacks", or "ui_select"
    },
  },
}
```

### Local Development / Linking

If you have cloned the repository locally to `~/git/super-markdown.nvim`:

```lua
{
  dir = vim.fn.expand("~/git/super-markdown.nvim"),
  name = "super-markdown.nvim",
  ft = { "markdown", "md" },
  opts = {},
}
```

---

## ⌨️ Default Keybindings

| Mode | Keymap | Command | Description |
| :--- | :--- | :--- | :--- |
| Normal | `<leader>mr` | `:SuperMarkdown toggle` | Toggle in-buffer live rendering |
| Normal | `<leader>mo` | `:SuperMarkdown toc` | Open Table of Contents (Telescope / Picker) |
| Normal | `<leader>ms` | `:SuperMarkdown toc_sidebar` | Toggle TOC outline sidebar |
| Normal | `<leader>mp` | `:SuperMarkdown mermaid` | Preview Mermaid diagram under cursor |
| Normal | `<leader>mx` | `:SuperMarkdown checkbox` | Toggle / cycle checkbox state |
| Normal | `<leader>mtf`| `:SuperMarkdown table_format`| Auto-format & align Markdown table |
| Normal | `<leader>ml` | `:SuperMarkdown link` | Follow Markdown link, `#anchor`, or `@impl`/`@test` file |
| Normal | `<leader>mK` | `:SuperMarkdown preview_ref` | Peek at linked file / line range in floating window |
| Normal | `<leader>mzM`| `:SuperMarkdown fold_all` | Fold all markdown sections (`zM`) |
| Normal | `<leader>mzR`| `:SuperMarkdown unfold_all` | Unfold all markdown sections (`zR`) |
| Normal | `<leader>mza`| `:SuperMarkdown fold_toggle` | Toggle fold under cursor (`za`) |
| Normal | `<leader>mss`| `:SuperMarkdown spec_dashboard`| Open Spec Health & Traceability Dashboard |
| Normal | `<leader>msp`| `:SuperMarkdown spec_pick` | Open Semantic Spec Picker (questions, reqs, diagrams, etc.) |
| Normal | `<leader>msl`| `:SuperMarkdown spec_lint` | Run Spec Linter for ambiguity & missing links |
| Normal | `<leader>msn`| `:SuperMarkdown spec_new` | Insert Spec Template (`architecture`, `feature`, `api`, `test_plan`) |
| Normal | `<leader>msd`| `:SuperMarkdown spec_status` | Cycle Spec Document Status (`DRAFT` ➔ `REVIEW` ➔ `APPROVED`...) |
| Normal | `<leader>my` | `:SuperMarkdown llm_context` | Copy Section + Linked Files LLM Context Bundle |
| Normal | `<leader>mgc`| `:SuperMarkdown llm_code` | Open LLM Implementation Code Prompt Studio |
| Normal | `<leader>mgt`| `:SuperMarkdown llm_tests` | Open LLM Application Test Suite Prompt Studio |
| Normal | `<leader>mgr`| `:SuperMarkdown llm_review` | Open LLM Spec Review & Co-Author Prompt Studio |
| Normal | `<leader>mrun`| `:SuperMarkdown run_block` | Execute code block under cursor inline |
| Insert | `<CR>` | *(smart list)* | Auto-continue list bullet / number |
| Normal/Insert | `<Tab>` | *(table)* | Jump to next table cell |
| Normal/Insert | `<S-Tab>` | *(table)* | Jump to previous table cell |

---

## ⚙️ Configuration

Here is the complete default configuration:

```lua
require("super-markdown").setup({
  enabled = true,
  filetypes = { "markdown", "md", "markdown.mdx" },
  debounce_ms = 70,

  render = {
    enabled = true,
    conceallevel = 2,
    concealcursor = "c", -- keeps current line revealed in normal/insert modes for easy editing
    headings = {
      enabled = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    },
    checkboxes = {
      enabled = true,
    },
    callouts = {
      enabled = true,
      border_char = "▍",
    },
    tables = {
      enabled = true,
      box_drawing = true,
    },
    codeblocks = {
      enabled = true,
      border = true,
      border_char = "│",
      width = 60,
      show_language = true,
    },
    dividers = {
      enabled = true,
      char = "─",
    },
    links = {
      enabled = true,
      icon = "󰌹 ",
    },
  },

  -- Markdown folding options (+ and - in gutter)
  folds = {
    enabled = true,
    foldcolumn = "1",       -- "1", "2", "auto" ("0" to disable fold column)
    foldlevel = 99,        -- initial fold level: 99 opens all on open; 0 folds all
    foldopen = "-",        -- gutter symbol for open fold
    foldclose = "+",       -- gutter symbol for closed fold
    foldsep = "│",         -- gutter symbol for open fold separator line
    foldtext = true,       -- styled foldtext with heading icon and line count
  },

  mermaid = {
    enabled = true,
    backend = "auto", -- "auto", "kitty", "ascii"
    theme = "dark",   -- "dark", "default", "forest", "neutral"
    preview_win = {
      width = 0.85,
      height = 0.85,
      border = "rounded",
    },
  },

  toc = {
    picker = "auto", -- "auto" (prefers telescope > snacks > ui_select)
    sidebar = {
      width = 36,
      position = "right", -- "left" or "right"
      border = "rounded",
    },
  },

  tools = {
    smart_lists = true,
    auto_link_paste = true,
    table_helpers = true,
  },

  keymaps = {
    toggle_render = "<leader>mr",
    toc = "<leader>mo",
    toc_sidebar = "<leader>ms",
    mermaid_preview = "<leader>mp",
    toggle_checkbox = "<leader>mx",
    format_table = "<leader>mtf",
    follow_link = "<leader>ml",
    fold_all = "<leader>mzM",
    unfold_all = "<leader>mzR",
    fold_toggle = "<leader>mza",
    table_next = "<Tab>",
    table_prev = "<S-Tab>",
  },
})
```

---

## 🧪 Testing

`super-markdown.nvim` includes a full automated test suite verifying TOC parsing, checkbox toggling, table formatting, mermaid extraction, and in-buffer rendering:

```bash
nvim --headless -u NONE -c "luafile tests/run_all.lua"
```

---

## 📄 License

MIT License. See [LICENSE](./LICENSE) for details.
