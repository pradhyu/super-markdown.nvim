# super-markdown.nvim (Specification & Architecture)

> **Vision**: The premier, all-in-one Markdown powerhouse for Neovim. Combines high-fidelity in-buffer live rendering, native terminal Mermaid diagram compilation and preview, an instant Telescope & Snacks TOC search engine, intelligent table formatting, and fluid note-taking mechanics into a blazing-fast, pure-Lua plugin.

---

## 1. Executive Summary & Motivations

### 1.1 The Markdown Dilemma in Neovim
Markdown is the lingua franca of documentation, research, task tracking, technical specifications, and knowledge management. However, the existing Neovim markdown ecosystem suffers from fragmentation:

| Existing Plugin | Strengths | Critical Limitations |
| :--- | :--- | :--- |
| `render-markdown.nvim` | In-buffer extmark rendering | ❌ No Mermaid diagram rendering<br>❌ No Telescope TOC outline<br>❌ No table navigation/auto-formatter |
| `iamcco/markdown-preview.nvim` | Full HTML/Mermaid preview | ❌ Out-of-editor experience (external browser)<br>❌ Heavy Node.js/Yarn build step<br>❌ Disconnects editing from reading |
| `markview.nvim` | Visual in-buffer decorations | ❌ Heavy performance overhead on large files<br>❌ Fragile Treesitter queries across updates<br>❌ No diagram preview engine |
| `3rd/image.nvim` | Terminal image rendering | ❌ Requires Luarocks/C Magick bindings<br>❌ Scrolling artifacts & high crash potential<br>❌ No markdown-specific diagram workflows |

### 1.2 The Solution: `super-markdown.nvim`
`super-markdown.nvim` unifies the modern markdown experience into a cohesive, zero-friction plugin designed to look gorgeous, operate asynchronously, and feel native to Neovim:

1. **Same-Buffer Live Rendering & Preview**:
   - In-buffer visual enhancement using Neovim extmarks, virtual lines, and conceal.
   - Heading banners, level icons, and subtle background highlights.
   - Interactive checkboxes (`[ ]`, `[x]`, `[-]`, `[/]`, `[!]`, `[?]`) with single-keystroke cycling.
   - Obsidian & GitHub callouts/admonitions (`[!NOTE]`, `[!TIP]`, `[!WARNING]`, `[!CAUTION]`, `[!IMPORTANT]`, `[!TODO]`).
   - Clean Box-Drawing table borders (`┌─┬─┐`, `│ │ │`, `├─┼─┤`, `└─┴─┘`).
   - Fenced code blocks with language badges and border frames.
   - Elegant horizontal dividers and concealed markdown link styling.
   - Instant toggle (`:SuperMarkdown toggle`) with zero delay.

2. **Full Mermaid Diagram Rendering Engine**:
   - Detects ````mermaid` fenced blocks across the buffer.
   - **Kitty Graphics Protocol Integration**: Native terminal rendering for Kitty, Ghostty, WezTerm terminals.
   - **Async Compiler & Image Pipeline**: Asynchronously renders diagram to SVG/PNG using local CLI (`mmdc`) or fast API (`mermaid.ink`) with SHA-256 disk caching.
   - **Floating Diagram Preview Popup** (`:SuperMarkdown mermaid_preview`): Floating terminal/image popup displaying rendered diagrams with high clarity.
   - **Zero-Dependency ASCII Fallback**: Built-in ASCII flowchart generator when offline or in legacy terminals.

3. **High-Speed TOC Viewer & Telescope Search**:
   - **Telescope Heading Finder** (`:SuperMarkdown toc`):
     - Hierarchical tree display with level icons and indented nesting.
     - Live fuzzy search across all document headings.
     - Real-time line preview with contextual cursor jump.
   - **Universal Fallback**: Automatic support for `snacks.picker`, `fzf-lua`, or `vim.ui.select` when Telescope is not installed.
   - **Document Outline Sidebar** (`:SuperMarkdown toc_sidebar`): Collapsible floating sidebar for persistent document navigation.

4. **Productivity & Authoring Tools**:
   - **Table Formatter & Navigator**: Auto-align column widths and delimiters; `<Tab>` / `<S-Tab>` cell jumping.
   - **Smart List Continuation**: Automatically continues unordered (`- `, `* `) and ordered (`1. `) lists; deletes prefix on blank double-enter.
   - **Smart Link Follow & Paste**: `gx` opens external URLs in browser or local markdown links in Neovim; pasting URLs over selected text automatically creates `[selection](url)`.

---

## 2. Architecture & Module Design

```
super-markdown.nvim/
├── lua/
│   └── super-markdown/
│       ├── init.lua             # Plugin entrypoint, setup, commands, lifecycle
│       ├── config.lua           # Options, highlight groups, default keymaps
│       ├── render/              # In-buffer rendering engine (extmarks & conceal)
│       │   ├── init.lua         # Buffer lifecycle, event debouncing, toggle state
│       │   ├── headings.lua     # Heading icons, backgrounds, conceal markers
│       │   ├── checkboxes.lua   # Checkbox icons, colors, interactive toggler
│       │   ├── callouts.lua     # Admonitions / callout bars and icons
│       │   ├── tables.lua       # Box-drawing table rendering
│       │   ├── codeblocks.lua   # Code block headers, language badges, borders
│       │   ├── divider.lua      # Horizontal rule dividers
│       │   └── links.lua        # Concealed links and icon badges
│       ├── mermaid/             # Mermaid diagram compilation & preview engine
│       │   ├── init.lua         # Block scanner, cursor detection, cache manager
│       │   ├── compiler.lua     # Async compilation (CLI / HTTP API / disk cache)
│       │   ├── terminal.lua     # Kitty graphics protocol escape sequence generator
│       │   ├── preview.lua      # Floating preview window (icat / image / ASCII)
│       │   └── ascii.lua        # Fallback ASCII flowchart renderer
│       ├── toc/                 # Table of Contents engine
│       │   ├── init.lua         # Heading scanner & hierarchical tree builder
│       │   ├── telescope.lua    # Telescope extension & picker
│       │   ├── snacks.lua       # Snacks.picker integration
│       │   ├── sidebar.lua      # Floating / split outline sidebar
│       │   └── picker.lua       # Universal picker dispatcher
│       └── tools/               # Editing utilities
│           ├── checkbox.lua     # Checkbox toggle logic
│           ├── list.lua         # Smart list auto-continuation
│           ├── table.lua        # Table formatter and cell jumper
│           └── link.lua         # Link follower & markdown URL paste helper
├── plugin/
│   └── super-markdown.lua       # Global commands & FileType autocommands
├── tests/
│   ├── render_spec.lua          # Extmark & parser unit tests
│   ├── mermaid_spec.lua         # Diagram extraction & compiler tests
│   └── toc_spec.lua             # Heading extraction & hierarchy tests
├── examples/
│   └── showcase.md              # Demonstration markdown document
├── README.md                    # User documentation & installation guide
└── SPEC.md                      # This specification
```

---

## 3. Detailed Component Specifications

### 3.1 In-Buffer Rendering Engine (`render/`)
- **Namespaces**:
  All extmarks use a dedicated namespace `vim.api.nvim_create_namespace("super_markdown_render")`.
  Clearing extmarks during re-render is instantaneous (`nvim_buf_clear_namespace`).
- **Event Debouncing**:
  Rendering triggers on `BufEnter`, `BufWinEnter`, `InsertLeave`, and debounced `TextChanged` (default 80ms).
  While in Insert mode on the active line, conceal is suspended on that line (`concealcursor = ""` or cursorline unhide) so editing remains completely natural and predictable.
- **Headings**:
  - H1: `󰲡 ` + bold title + full/padded background highlight (`SuperMarkdownH1`)
  - H2: `󰲣 ` + bold title + background highlight (`SuperMarkdownH2`)
  - H3: `󰲥 ` + colored title (`SuperMarkdownH3`)
  - H4: `󰲧 ` + colored title (`SuperMarkdownH4`)
  - H5: `󰲩 ` + colored title (`SuperMarkdownH5`)
  - H6: `󰲫 ` + colored title (`SuperMarkdownH6`)
- **Checkboxes**:
  - `[ ]` -> `󰄱 ` (`SuperMarkdownCheckboxUnchecked`)
  - `[x]` / `[X]` -> `󰄵 ` (`SuperMarkdownCheckboxChecked`)
  - `[-]` -> `󰡖 ` (`SuperMarkdownCheckboxCanceled`)
  - `[/]` -> `󰄰 ` (`SuperMarkdownCheckboxProgress`)
  - `[!]` -> `󰀦 ` (`SuperMarkdownCheckboxImportant`)
  - `[?]` -> `󰋽 ` (`SuperMarkdownCheckboxQuestion`)
- **Callouts**:
  Matches `> [!TYPE] Title`:
  - `NOTE`: `󰋽 Note` (Blue/Cyan)
  - `TIP`: `󰌶 Tip` (Green)
  - `IMPORTANT`: `󰅒 Important` (Purple)
  - `WARNING`: `󰀦 Warning` (Yellow/Orange)
  - `CAUTION` / `DANGER`: `󰳦 Caution` (Red)
  - `TODO`: `󰄱 Todo` (Teal)
  - `QUESTION`: `󰋽 Question` (Magenta)
  Virtual line prefix `▍ ` added to all subsequent quote lines.

### 3.2 Mermaid Diagram Engine (`mermaid/`)
- **Block Parsing**:
  Scans buffer for lines starting with ```` ```mermaid ```` to ```` ``` ````.
- **Cache Management**:
  Hash of diagram code: `sha256(diagram_code)`.
  Cache location: `vim.fn.stdpath("cache") .. "/super_markdown/mermaid/"`.
  If cached PNG exists, skip network/CLI and display immediately.
- **Compilation Cascade**:
  1. Local CLI: Check for `mmdc` executable in `$PATH`.
  2. Cloud API: Async HTTPS POST to `https://mermaid.ink/svg/<base64>` or `kroki.io` using `vim.system({"curl", ...})`.
  3. Image conversion: Uses `/usr/bin/magick` (or `rsvg-convert`) to convert SVG to high-res PNG.
  4. ASCII Fallback: Built-in deterministic text graph generator if offline or CLI unavailable.
- **Display Modes**:
  - **Inline Status Extmark**: Displays `󰡷 [Mermaid: Ready | Press <leader>mp to preview]` above diagram.
  - **Floating Preview Window (`<leader>mp`)**:
    - If running in Kitty terminal: Launches floating popup terminal with `kitten icat --align center <cached_png>`, or streams Kitty graphics protocol escape codes!
    - Fallback: Formatted ASCII diagram rendered in floating window with syntax highlighting.
    - Keymap inside preview: `o` to open in external viewer (`xdg-open`), `q` to close.

### 3.3 TOC Viewer & Telescope Integration (`toc/`)
- **Heading Extraction**:
  Traverses buffer lines or Treesitter markdown AST.
  Extracts: line number, level (1-6), title text, anchor slug.
- **Telescope Picker**:
  - Formatted display:
    ```
    󰲡 Architecture Overview             [L14]
      󰲣 In-Buffer Rendering Pipeline    [L45]
        󰲥 Extmarks & Virtual Lines      [L82]
      󰲣 Mermaid Diagram Engine          [L110]
    ```
  - Custom displayer with icons and indentation.
  - Live buffer previewer centered on heading location.
  - `<CR>` jumps to heading, folds unfold automatically (`zv`).
- **Fallback Picker**:
  Gracefully selects `Snacks.picker.select` or `vim.ui.select` if Telescope is not installed.
- **Sidebar Outline**:
  Toggleable right/left split or floating window displaying the hierarchy.

### 3.4 Editing Utilities (`tools/`)
- `toggle_checkbox()`:
  Cycles current line or visual selection through checkbox states.
- `smart_list_enter()`:
  Insert mode `<CR>` handler. Preserves indent and bullet; cleans empty bullet on consecutive Enter.
- `format_table()`:
  Calculates maximum width per column, reformats all cells with uniform padding, preserves column alignment markers.
- `follow_link()`:
  Detects `[text](target)` under cursor.
  If `target` begins with `http://` or `https://`, opens via `xdg-open` / browser.
  If `target` is a file path (e.g. `./notes.md`), opens in Neovim buffer.

---

## 4. Keybindings & User Experience

| Mode | Keymap | Command | Description |
| :--- | :--- | :--- | :--- |
| Normal | `<leader>mr` | `:SuperMarkdown toggle` | Toggle in-buffer rendering |
| Normal | `<leader>mo` | `:SuperMarkdown toc` | Open Table of Contents (Telescope / Picker) |
| Normal | `<leader>ms` | `:SuperMarkdown toc_sidebar` | Toggle TOC outline sidebar |
| Normal | `<leader>mp` | `:SuperMarkdown mermaid_preview` | Preview Mermaid diagram under cursor |
| Normal | `<leader>mx` | `:SuperMarkdown checkbox_toggle` | Toggle/cycle checkbox under cursor |
| Normal | `<leader>mtf` | `:SuperMarkdown table_format` | Auto-format current Markdown table |
| Normal | `<leader>ml` | `:SuperMarkdown follow_link` | Follow link under cursor |
| Insert | `<CR>` | (smart list enter) | Auto-continue list bullet / number |
| Normal/Insert | `<Tab>` | `:SuperMarkdown table_next` | Jump to next table cell |
| Normal/Insert | `<S-Tab>` | `:SuperMarkdown table_prev` | Jump to previous table cell |

---

## 5. Summary
`super-markdown.nvim` delivers an uncompromising, modern markdown environment for Neovim: combining native terminal graphics, in-buffer visual elegance, and lightning-fast search navigation into a cohesive, robust package.
