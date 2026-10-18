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
- **Live In-Buffer Rendering (`virt_lines`)**: Diagrams are parsed and rendered directly beneath the code block as clean, connected Unicode diagrams that scroll naturally with the buffer.
- **Full Diagram Type Support**: Flowcharts (TD, LR with shapes & edge labels), Sequence Diagrams (participants, lifelines, message arrows, step numbers, self-calls), and State Machines.
- **Terminal Graphics & Floating Preview (`<leader>mp`)**: Pixel-perfect Kitty Graphics Protocol rendering via `kitten icat` inside floating popup windows when high-resolution image preview is desired.
- **Instant SHA-256 Disk Caching**: Compiled diagrams are cached in `~/.cache/nvim/super_markdown/mermaid/`, making subsequent renders instantaneous (0ms).

### 3. High-Speed TOC Viewer with Telescope Search
- **Telescope Heading Finder (`<leader>mo`)**:
  - Hierarchical tree display with indented level icons.
  - Live fuzzy search across all document headings.
  - Contextual split previewer highlighting the exact line in your buffer.
  - `<CR>` jumps to the heading and unfolds folds (`zv`).
- **Universal Fallback**: Automatically integrates with `Snacks.picker` or `vim.ui.select` if Telescope is not installed.
- **Document Outline Sidebar (`<leader>ms`)**: Floating / split outline sidebar displaying the document table of contents.

### 4. Automated Table Alignment & Authoring Tools
- **Automated In-Line Column Alignment**: Ragged or unaligned Markdown tables are automatically rendered with perfectly aligned columns, custom alignment indicators (`:---`, `:---:`, `---:`), and box-drawing borders without modifying the buffer text.
- **Source Formatter (`<leader>mtf`)**: Explicitly formats and snaps the buffer text itself into clean Markdown spacing.
- **Table Cell Navigation**: Press `<Tab>` to jump to the next cell and `<S-Tab>` to the previous cell. Pressing `<Tab>` on the last cell automatically adds a new row!
- **Smart List Continuation**: Pressing `<CR>` in insert mode automatically continues unordered (`- `, `* `, `+ `) and numbered (`1. `) lists.
- **Smart Link Follow & Paste (`<leader>ml` / `gx`)**: Open URLs in your browser or jump directly to local Markdown notes.

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
| Normal | `<leader>ml` | `:SuperMarkdown link` | Follow Markdown link under cursor |
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
# super-markdown.nvim
# super-markdown.nvim
# super-markdown.nvim
