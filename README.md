# 🚀 super-markdown.nvim

<div align="center">

**The premier, all-in-one Markdown powerhouse for Neovim.**

*High-fidelity in-buffer live rendering • Focus Mode spotlight • Native terminal Mermaid preview • High-speed Telescope & Snacks TOC search • Intelligent table & spec authoring tools*

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

### 1. In-Buffer Live Rendering & Enhanced Human Readability
Render Markdown elements directly inside your active buffer without losing your cursor or editing context:
- **Headings**: Styled level icons (`󰲡 `, `󰲣 `, `󰲥 `, `󰲧 `, `󰲩 `, `󰲫 `) with visually indented hierarchy corresponding to heading depth.
- **Interactive Checkboxes & Lists**:
  - `[ ]` ➔ `󰄱 ` (Unchecked; conceals the raw `- ` bullet for clean typography: `󰄱 Task`)
  - `[x]` ➔ `󰄵 ` (Checked, highlighted)
  - `[-]` ➔ `󰡖 ` (Canceled with automatic strikethrough styling)
  - `[/]` ➔ `󰄰 ` (In-progress)
  - `[!]` ➔ `󰀦 ` (Important)
  - `[?]` ➔ `󰋽 ` (Question)
  - Single-keystroke toggle or cycle with `<leader>mx`.
  - Nested standard unordered lists render beautiful typographic bullets (`•`, `◦`, `▪`, `▫`) reflecting nesting depth.
- **GitHub & Obsidian Callouts & Blockquotes**:
  - Styled admonition blocks with left vertical accent bar: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`, `> [!DANGER]`, `> [!TODO]`.
  - Standard blockquotes rendered with a subtle vertical border `▍` and styled text.
- **Box-Drawing Tables**: Delimiter rows and pipes dynamically styled with clean Unicode box-drawing characters (`┌─┬─┐`, `│ │ │`, `├─┼─┤`, `└─┴─┘`) with raw alignment colons (`:---:`) cleanly hidden and headers accented.
- **Code Block Badges & Borders**: Language icon tab banners rendered cleanly on opening fences (`󰢱 lua`, `󰌠 python`, `󰛦 rust`, `󰡷 mermaid`) with matching closing bottom borders without duplicate empty lines.
- **Horizontal Dividers**: `---`, `***` replaced with elegant full-width divider lines.
- **Concealed Links**: URLs concealed while link text is styled with `󰌹 ` and underlined.

### 2. Focus Mode (Spotlight Active Block, Dim Others)
Stay in flow when reading or writing long technical documents:
- **Spotlight Active Block (`<leader>mf` / `:SuperMarkdown focus`)**: Dims all surrounding Markdown text while leaving the block under your cursor crisp and highlighted.
- **Granular Scopes**:
  - `scope = "toc"` *(Default)*: Highlights the active Table of Contents section (from the current heading to the next heading in the TOC). The first root mentioned in the TOC is spotlighted while the rest of the document is dimmed.
  - `scope = "root"`: Highlights the entire active root section in the TOC hierarchy.
  - `scope = "section"`: Highlights the section from the current heading down to the next heading of the same or higher level.
  - `scope = "block"`: Highlights the immediate paragraph, fenced code block, table, callout blockquote, or list item.
  - Quickly switch scopes via `:SuperMarkdown focus toc`, `:SuperMarkdown focus root`, `:SuperMarkdown focus section`, or `:SuperMarkdown focus block`.
- **Dual-Tier Detection Engine**: High-precision Treesitter AST parsing with an instant pure-Lua regex fallback.
- **Zero-Flicker Ephemeral Rendering**: Powered by Neovim's `nvim_set_decoration_provider` using ephemeral extmarks—zero buffer modification, zero undo contamination, and instant updates as your cursor moves.

### 3. Automated In-Line Mermaid Diagram Engine
Write ```` ```mermaid ```` diagrams and have them **render automatically in line** directly inside the active buffer—no manual preview required:
- **Dual Engine Options (`termaid` vs Internal)**:
  - **`termaid` Engine**: Seamlessly integrates with the [termaid](https://github.com/fasouto/termaid) CLI when available. Uses `--format styled-json` to preserve rich semantic tokens (`node`, `edge`, `arrow`, `label`, `edge_label`, `subgraph`) as live Neovim extmarks, with A* edge routing, branch turns, and support for all 18 Mermaid diagram types (flowchart, sequence, class, state, er, gitgraph, gantt, pie, mindmap, etc.).
  - **Upgraded Pure-Lua Internal Engine**: Zero external dependencies. Upgraded with true 2D multi-branch horizontal (`LR` / `RL`) flowcharts, decision diamond routing, class hierarchy arrows (`△`), and ER entity connectors.
  - **Flexible Engine Configuration (`renderer = "auto" | "termaid" | "internal"`)**: Set `renderer = "auto"` (default, uses `termaid` if installed or in `$PATH`, else internal), `"termaid"`, or `"internal"`.
  - **Live Runtime Switching**: Switch between engines dynamically using `:SuperMarkdown mermaid_renderer [auto|termaid|internal]` or press `t` inside the `<leader>mp` floating preview window to instantly compare renders!
- **Full Syntax Highlighting**: Real-time syntax highlighting for raw Mermaid text (keywords, directions, connectors/arrows, node shapes & brackets, pipe edge labels, comments, strings, styles, and hex colors) powered by live buffer extmarks and standard Vim syntax (`syntax/mermaid.vim`).
- **Live In-Buffer Rendering (`virt_lines`)**: Diagrams are parsed and rendered directly beneath the code block as clean, connected Unicode diagrams that scroll naturally with the buffer.
- **Full Diagram Type Support**: Flowcharts (TD, LR with shapes & edge labels), Sequence Diagrams (participants, lifelines, message arrows, step numbers, self-calls), State Machines, Class Diagrams, and ER Diagrams.
- **Terminal Graphics & Floating Preview (`<leader>mp`)**: Pixel-perfect Kitty Graphics Protocol rendering via `kitten icat` inside floating popup windows when high-resolution image preview is desired, with `t` shortcut to toggle between text engines.
- **Instant SHA-256 Disk Caching**: Compiled diagrams are cached in `~/.cache/nvim/super_markdown/mermaid/`, making subsequent renders instantaneous (0ms).

### 4. Live Synchronized Side Preview Pane
- **Side-by-Side Read-Only Split (`<leader>mv` / `:SuperMarkdown preview`)**: Opens a dedicated read-only right vertical split previewing the rendered markdown document while you edit the raw source on the left.
- **Bi-Directional Scroll Synchronization**: Moving in the editor smoothly synchronizes line positions in the preview window and vice-versa.
- **Reader Mode (`<leader>mV` / `:SuperMarkdown preview reader`)**: Hides fold columns, line numbers, and signs for a serene reading experience.
- **Toggle Focused Editor Mode (`<leader>me` / `:SuperMarkdown editor`)**: Hides distracting UI elements in the editing buffer to optimize focus.

### 5. High-Speed TOC Viewer with Telescope Search
- **Telescope Heading Finder (`<leader>mo`)**:
  - Hierarchical tree display with indented level icons in natural top-to-bottom document order.
  - Live fuzzy search across all document headings.
  - Contextual split previewer that automatically scrolls to and highlights the target heading in the preview window.
  - `<CR>` jumps to the heading and unfolds folds (`zv`).
- **Universal Fallback**: Automatically integrates with `Snacks.picker` or `vim.ui.select` if Telescope is not installed.
- **Document Outline Sidebar (`<leader>ms`)**:
  - Split outline sidebar displaying the document table of contents.
  - **Dynamic Document Focus & Auto-Switching (`auto_switch_buffer = true`)**: The sidebar stays open and docked, automatically reloading itself to reflect whichever markdown file or window is currently focused (`BufEnter` / `WinEnter`). Switching between markdown splits (e.g. between `SPEC.md`, `ARCHITECTURE.md`, or `examples/showcase.md`) seamlessly updates the TOC outline and sync highlighting to match the active document.
  - **Per-Document State Isolation**: Collapsed sections are tracked per buffer, so collapsing a section in File A does not affect File B.
  - **Unified Docked Workspace**: A single docked sidebar dynamically serves all markdown buffers across your editor without cluttering splits with redundant sidebars.
  - Live scrolling: moving up and down the sidebar automatically scrolls the markdown viewer to the highlighted section.
  - **Scroll-to-Top Positioning (`scroll_to_top = true`)**: When moving selection or jumping in the sidebar, places the target heading right at the top of the viewing screen (`zt`) instead of centering it (`zz`), so you can read downward from the section header immediately.
  - **Instant Top/Center Toggle (`z` / `Z` in sidebar or `<leader>mzT`)**: Toggle between Top (`zt`) and Center (`zz`) positioning on the fly. The active mode is displayed in the sidebar banner (`Top(z)` ↔ `Ctr(z)`).
  - Pressing `<CR>` jumps to the selected heading and switches focus directly to the markdown viewer.

### 6. Sticky Stacked Headers (Pinned Section Context)
- **Pinned Context Stack (`<leader>mH` / `:SuperMarkdown sticky`)**:
  - As you scroll down through long specifications in either the **editor** or the **live preview pane**, parent headings that have scrolled past the top of the window are pinned in a lightweight sticky context float at the top of the screen:
    ```
     󰲡 1. System Architecture
       󰲣 1.1 Backend Services
         󰲥 1.1.1 Authentication Pipeline
    ────────────────────────────────────────────
    ```
  - You always know exactly which section, subsection, and parent architecture boundary you are currently inside.
  - **Auto-Stack & Auto-Shrink**: As you scroll deeper, subsections stack; as you scroll back up, headings pop off the stack as soon as they become visible in the buffer.
  - **Interactive Jump**: Clicking with mouse or pressing `<CR>` on any stacked header jumps directly to that section.
  - **Fully Optional**: Easily enabled or disabled via configuration (`sticky.enabled = true`), shortcut (`<leader>mH`), sidebar (`X`), or command (`:SuperMarkdown sticky`).

### 7. Automated Table Alignment & Authoring Tools
- **Automated In-Line Column Alignment**: Ragged or unaligned Markdown tables are automatically rendered with perfectly aligned columns, custom alignment indicators (`:---`, `:---:`, `---:`), and box-drawing borders without modifying the buffer text.
- **Source Formatter (`<leader>mtf`)**: Explicitly formats and snaps the buffer text itself into clean Markdown spacing.
- **Table Cell Navigation**: Press `<Tab>` to jump to the next cell and `<S-Tab>` to the previous cell. Pressing `<Tab>` on the last cell automatically adds a new row!
- **Smart List Continuation**: Pressing `<CR>` in insert mode automatically continues unordered (`- `, `* `, `+ `) and numbered (`1. `) lists.
- **Smart Link Follow & Paste (`<leader>ml` / `gx`)**: Open URLs in your browser or jump directly to local Markdown notes.

### 7. Unified Expand, Collapse & Surround Folding Across All Views
Folding in `super-markdown.nvim` works like surround text objects—synchronized across all 3 active surfaces: the **TOC Sidebar**, the **Edit Markdown View**, and the **Live Preview Pane**:

- **Cross-View Synchronization**:
  - Collapsing or expanding any heading in the **sidebar** collapses or expands its fold in both the **edit markdown view** and the **read-only live preview pane**.
  - Collapsing or expanding in the **editor** or **preview pane** instantly updates the sidebar outline (hiding/revealing nested descendant headings and updating the `▸` / `▾` indicator and `⋯ (+N)` count).
  - Collapsing all (`zM`) or expanding all (`zR`) operates globally across sidebar, editor, and preview simultaneously.
- **Hierarchical Tree Outline in Sidebar**:
  - Headings with nested child sections show `▾ ` when expanded and `▸ ` when collapsed.
  - Collapsing a parent heading hides all its descendant subheadings from the sidebar list and displays a count badge (e.g. `▸ 󰲡 Architecture Overview  ⋯ (+3)`).
- **Universal Vim Fold Shortcuts across Sidebar, Editor & Preview**:
  - `za` or `<Space>`: Toggle heading fold (synchronized across sidebar, editor & preview).
  - `zc` or `-`: Collapse heading & all child subheadings (synchronized).
  - `zo` or `+`: Expand heading (synchronized).
  - `zM` or `<leader>mzM`: Collapse all sections across all three views.
  - `zR` or `<leader>mzR`: Expand all sections across all three views.
  - `zm`: Fold more (decrease foldlevel / collapse deepest visible level).
  - `zr`: Fold less (increase foldlevel / expand next collapsed level).
  - **Deep 6-Level Hierarchy Testing**: Supports deep H1 → H2 → H3 → H4 → H5 → H6 nesting; `zm` and `zr` step progressively through each level across all three views (see `examples/showcase.md` for a full 6-level architecture demonstration).
  - `<CR>` in preview pane: If on a heading line, toggles fold in place; if on body text, jumps to editable source at that exact line.
  - `<CR>` in sidebar: Jumps to and unfolds heading in editor and preview.
- **Stylized Fold Text & Gutter Indicators**:
  - Gutter indicators: `-` for open fold, `+` for closed fold, `│` for fold separator line.
  - Fold text displays folder icon, heading level icon, section title, spec task completion summary (`[󰄵 3/5 · 󰀦 1 · 󰋽 1]`), and folded line count.

### 8. Spec-Driven Development (SDD) & LLM Workflow Suite
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

### 9. Human-in-the-Loop Review & AI Agent Change Eyeballer
As markdowns have become the **new executable code for specifications written by AI agents** (Cursor, Claude Code, Cline, Aider, Devin, Gemini CLI, Copilot Workspace), human reviewers need to quickly go over, review, and eyeball massive agent-generated markdown files without getting drowned in boilerplate prose:

- **Interactive Spec Review Cockpit HUD (`<leader>mrs` / `:SuperMarkdown review_session`)**:
  - Floating bottom-docked review stepper that walks you through the specification section-by-section while automatically scrolling and centering the background editor.
  - Displays live Git diff telemetry (`git: +X ~Y -Z`), task progress, open questions, blockers, and security/DB hazard alerts.
  - Single-key actions: `a` approve section, `r` request revision with reason, `?`/`Q` direct AI agent, `c` comment, `x`/`e` export directives to clipboard, `n`/`j` next section, `p`/`k` previous section.
- **Domain Entity & Contract Invariant Validator (`<leader>mSi` / `:SuperMarkdown invariants`)**:
  - Cross-section consistency auditor that extracts HTTP endpoints, environment variables, SQL tables, and error codes to flag route pluralization drift (e.g., `/v2/charges` vs `/v2/charge`), undeclared environment variables in code blocks, and missing idempotency headers.
- **Bidirectional Requirement-to-Code Traceability Matrix (`<leader>mSt` / `:SuperMarkdown traceability`)**:
  - Interactive floating tree mapping every `REQ-*`, `AC-*`, and `Scenario:` block to its `@impl:` and `@test:` repository files, computing live implementation and test coverage percentages with `<CR>` jump-to-file.
- **Interactive Spec Eyeballer & Scorecard HUD (`<leader>mE` / `:SuperMarkdown eyeball`)**:
  - Interactive floating dashboard giving you an executive birds-eye view:
    - **Speed & Length Metrics**: Total lines, word count, estimated deep reading time vs 30-second skim time.
    - **Spec Readiness Score**: (0-100) combining task completion, acceptance criteria coverage, unresolved questions, blockers, and risk flags.
    - **Review Matrix by Section**: Displays each section with a review badge (`[󰄵 APPROVED]`, `[󰀦 REVISION]`, `[󰋽 QUESTION]`, or `[󰄱 UNREVIEWED]`), task tally (`󰄵 4/4`), risk tally (`󰳦 1 risk`), and line number.
    - **Single-Key Actions inside HUD**: Navigate freely with `j`/`k`, press `<CR>` to jump to section, `a` to approve, `r` to request revision, `?`/`Q` to add directive, `s` to toggle Skim mode, `e` to export feedback prompt!
- **Executive Skim / X-Ray Mode (`<leader>msm` / `:SuperMarkdown skim`)**:
  - Automatically dims dense prose paragraphs, instantly highlighting only the structural skeleton of the spec: headings, tables, BDD scenarios, checklists, callouts, and Mermaid diagrams. Eyeball a 2,000-line spec in under 30 seconds!
- **AI Boilerplate & Fluff Radar**:
  - Automatically identifies, dims, and flags conversational AI filler (*"Certainly!"*, *"Without further ado"*, *"As an AI language model"*, *"In this section we will discuss..."*) with `󰚩 AI Fluff` badges.
- **Critical Risk & Destructive Operation Radar**:
  - High-visibility margin badges and highlights for destructive commands (`rm -rf`, `DROP TABLE`, `kill -9`), hardcoded secrets (`password: '...'`, `token: '...'`), security hazards (`chmod 777`, `verify=False`), and breaking changes (`BREAKING:`, `schema migration`).
- **Acceptance Criteria & BDD Scenarios (Given / When / Then)**:
  - Formatted pill badges for BDD steps (`󰄱 Given `, `󰄱 When `, `󰄵 Then `, ` ↳ And `) and `AC-*` requirement IDs.
- **Full Human Review Lifecycle & Agent Prompt Export**:
  - `<leader>mra` (`:SuperMarkdown review_approve`): Approve active section with reviewer timestamp.
  - `<leader>mrr` (`:SuperMarkdown review_reject`): Request revisions from AI agent on active section.
  - `<leader>mrq` (`:SuperMarkdown review_question`): Add directive/question for AI agent (`> [!QUESTION] @agent: ...`).
  - `<leader>mrc` (`:SuperMarkdown review_comment`): Insert inline human review comment (`> [!REVIEW] @human: ...`).
  - `<leader>mrA` (`:SuperMarkdown review_approve_all`): Stamp entire document as `APPROVED` with reviewer username and date.
  - `<leader>mrR` (`:SuperMarkdown review_reject_all`): Stamp entire document as `REJECTED` / `CHANGES_REQUESTED`.
  - `<leader>mre` (`:SuperMarkdown review_export`): Assembles all review comments, questions, rejections, and blockers into a structured prompt copied to your clipboard and opened in the prompt studio to dispatch back to the agent!
- **Agent Change Eyeballer HUD (`<leader>mdc` / `:SuperMarkdown diff_hud`)**:
  - Floating dashboard analyzing changes against `git HEAD`: total insertions/modifications/deletions, which specific sections the agent touched, which requirements were modified, and which tasks were completed. Press `<CR>` on any hunk to jump directly to it.
- **In-Buffer Spec Change Highlights (`<leader>md` / `:SuperMarkdown diff`)**:
  - Live gutter indicators (`▎+`, `▎~`, `▎-`) and inline change badges (`󰜥 +3 Added`, `󰜥 ~2 Modified`, `▾ Deleted lines`).
- **Expanded Callouts for Agent Specifications**:
  - Distinct styling for `[!APPROVED]`, `[!REJECTED]`, `[!AGENT]`, `[!DECISION]`, `[!ASSUMPTION]`, `[!SECURITY]`, `[!BREAKING]`, `[!PERFORMANCE]`, `[!RISK]`, `[!RATIONALE]`, `[!PROMPT]`, `[!REVIEW]`.
- **Rapid Eyeball Navigation Jumps**:
  - `]w` / `[w`: Jump to next / previous critical risk or destructive operation.
  - `]a` / `[a`: Jump to next / previous ambiguity or AI fluff phrase.
  - `]s` / `[s`: Jump to next / previous BDD scenario or acceptance criteria (`AC-*`).
  - `]k` / `[k`: Jump to next / previous human review note or directive.
  - `]c` / `[c`: Jump to next / previous agent change hunk.
  - `]r` / `[r`: Jump to next / previous requirement ID (`REQ-*`, `AC-*`).
  - `]q` / `[q`: Jump to next / previous open question (`[?]`).
  - `]b` / `[b`: Jump to next / previous blocker (`[!]`).
  - `]t` / `[t`: Jump to next / previous pending task (`[ ]`, `[/]`).
- **Live Spec Statusline / Winbar Component**:
  - Zero-overhead status string via `require("super-markdown").statusline()` for `lualine`, `heirline`, or native `statusline`:
    `󰍔 Spec: 85% [APPROVED] │ 󰄵 12/15 │ 󰀦 1 │ 󰳦 0 │ [SKIM]`

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
| Normal | `<leader>mf` | `:SuperMarkdown focus` | Toggle Focus Mode (spotlight active block/section) |
| Normal | `<leader>msm`| `:SuperMarkdown skim` | Toggle Executive Skim / X-Ray Mode (prose dimmer) |
| Normal | `<leader>mE` | `:SuperMarkdown eyeball` | Open Interactive Spec Eyeballer & Scorecard HUD |
| Normal | `<leader>mv` | `:SuperMarkdown preview` | Open synchronized side-by-side preview pane |
| Normal | `<leader>mV` | `:SuperMarkdown preview reader` | Open full Reader Mode (distraction-free split) |
| Normal | `<leader>me` | `:SuperMarkdown editor` | Toggle focused editor mode (hide gutter/signs) |
| Normal | `<leader>ma` | `:SuperMarkdown auto_refresh` | Toggle live background auto-refresh in preview |
| Normal | `<leader>mo` | `:SuperMarkdown toc` | Open Table of Contents (Telescope / Picker) |
| Normal | `<leader>ms` | `:SuperMarkdown toc_sidebar` | Toggle TOC outline sidebar |
| Normal | `<leader>mp` | `:SuperMarkdown mermaid` | Preview Mermaid diagram under cursor |
| Normal | `<leader>mm` | `:SuperMarkdown mermaid_toggle` | Toggle Mermaid renderer on the fly (Termaid ↔ Internal) |
| Normal | — | `:SuperMarkdown mermaid_renderer [auto\|termaid\|internal]` | Switch Mermaid text renderer engine |
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
| Normal | `<leader>md` | `:SuperMarkdown diff` | Toggle Git Spec change highlights (`+`, `~`, `▾`) |
| Normal | `<leader>mdc`| `:SuperMarkdown diff_hud` | Open Agent Spec Changes Eyeballer HUD |
| Normal | `]c` / `[c` | `:SuperMarkdown next/prev_change` | Jump to next / previous agent change hunk |
| Normal | `]w` / `[w` | `:SuperMarkdown next/prev_risk` | Jump to next / previous critical risk / hazard |
| Normal | `]a` / `[a` | `:SuperMarkdown next/prev_fluff` | Jump to next / previous ambiguity or AI fluff phrase |
| Normal | `]s` / `[s` | `:SuperMarkdown next/prev_scenario` | Jump to next / previous BDD scenario / acceptance criteria |
| Normal | `]k` / `[k` | `:SuperMarkdown next/prev_review` | Jump to next / previous human review directive |
| Normal | `]r` / `[r` | `:SuperMarkdown next/prev_req` | Jump to next / previous requirement (`REQ-*`, `AC-*`) |
| Normal | `]q` / `[q` | `:SuperMarkdown next/prev_question` | Jump to next / previous open question (`[?]`) |
| Normal | `]b` / `[b` | `:SuperMarkdown next/prev_blocker` | Jump to next / previous blocker (`[!]`) |
| Normal | `]t` / `[t` | `:SuperMarkdown next/prev_task` | Jump to next / previous pending task (`[ ]`) |
| Normal | `<leader>mrs`| `:SuperMarkdown review_session` | Open Interactive Spec Review Cockpit HUD |
| Normal | `<leader>mSi`| `:SuperMarkdown invariants` | Check Domain Entity & Contract Invariants |
| Normal | `<leader>mSt`| `:SuperMarkdown traceability` | Open Bidirectional Requirement-to-Code Traceability Matrix |
| Normal | `<leader>mra`| `:SuperMarkdown review_approve` | Stamp active section as human `[!APPROVED]` |
| Normal | `<leader>mrr`| `:SuperMarkdown review_reject` | Request active section revision `[!REJECTED]` |
| Normal | `<leader>mrq`| `:SuperMarkdown review_question` | Leave directive/question for AI agent `[!QUESTION]` |
| Normal | `<leader>mrc`| `:SuperMarkdown review_comment` | Insert inline human review comment `[!REVIEW]` |
| Normal | `<leader>mrA`| `:SuperMarkdown review_approve_all` | Mark entire specification `APPROVED` |
| Normal | `<leader>mrR`| `:SuperMarkdown review_reject_all` | Request changes on entire specification |
| Normal | `<leader>mre`| `:SuperMarkdown review_export` | Export structured review feedback prompt for agent |
| Normal | `<leader>mb` | `:SuperMarkdown breadcrumb` | Show active section breadcrumb & metric HUD |
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
    concealcursor = "nc", -- keeps current line concealed in normal/command mode, revealed in insert
    headings = {
      enabled = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      folder_icon = false, -- cleaner heading typography without redundant folder icon
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

  -- Focus Mode (Spotlight active block, dim others)
  focus = {
    enabled = false,       -- enable on startup (disabled by default)
    scope = "toc",         -- "toc" (focuses TOC heading section), "root", "section", or "block"
    dim_hl = "SuperMarkdownDimmed",
    priority = 250,        -- high priority to wash out syntax on dimmed lines
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
    renderer = "auto", -- "auto" (prefers termaid if installed, else internal), "termaid", "internal"
    termaid = {
      cmd = "termaid", -- command or path to termaid CLI
      format = "styled-json", -- "styled-json" (preserves colors/tokens) or "text"
      arrow_style = "pointer", -- "pointer" (►), "triangle" (▶), "outline" (▷)
      padding_x = 2,
      padding_y = 1,
      gap = 2,
      width = nil, -- integer or nil (auto-fits buffer/window)
      ascii = false, -- use ASCII characters instead of Unicode box-drawing
      theme = nil, -- optional rich color theme
    },
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
    toggle_mermaid_renderer = "<leader>mm",
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
