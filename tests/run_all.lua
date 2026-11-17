-- Headless test runner for super-markdown.nvim
vim.opt.runtimepath:prepend(vim.fn.expand("~/git/super-markdown.nvim"))
local function add_plugin(path)
  local p = vim.fn.expand(path)
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:append(p)
    package.path = package.path .. ";" .. p .. "/lua/?.lua;" .. p .. "/lua/?/init.lua"
  end
end
add_plugin("~/.local/share/nvim/lazy/plenary.nvim")
add_plugin("~/.local/share/nvim/lazy/telescope.nvim")

local sm = require("super-markdown")
sm.setup({})
vim.cmd("runtime! plugin/super-markdown.lua")

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("  FAIL: %s (expected %s, got %s)", msg or "", vim.inspect(expected), vim.inspect(actual)))
  end
end

print("=== Running super-markdown.nvim Test Suite ===")

-- 1. Test TOC Extraction
print("\n[Test 1] TOC Heading Extractor")
local test_lines = {
  "# Title H1",
  "Some paragraph text",
  "## Section H2",
  "### Subsection H3",
  "```lua",
  "# not a heading in code",
  "```",
  "## Conclusion H2",
}
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, test_lines)

local toc = require("super-markdown.toc")
local headings = toc.get_headings(test_buf)
assert_eq(#headings, 4, "TOC should find exactly 4 headings")
assert_eq(headings[1].title, "Title H1", "H1 title match")
assert_eq(headings[1].level, 1, "H1 level match")
assert_eq(headings[2].level, 2, "H2 level match")
assert_eq(headings[3].level, 3, "H3 level match")
assert_eq(headings[4].title, "Conclusion H2", "H2 conclusion match")

-- 2. Test Checkbox Toggle
print("\n[Test 2] Checkbox Toggle Tool")
local cb_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(cb_buf, 0, -1, false, { "- [ ] Task item" })
vim.api.nvim_set_current_buf(cb_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local cb_tool = require("super-markdown.tools.checkbox")
cb_tool.toggle(false)
local toggled_line = vim.api.nvim_buf_get_lines(cb_buf, 0, 1, false)[1]
assert_eq(toggled_line, "- [x] Task item", "Unchecked toggled to checked")

cb_tool.toggle(false)
local untoggled_line = vim.api.nvim_buf_get_lines(cb_buf, 0, 1, false)[1]
assert_eq(untoggled_line, "- [ ] Task item", "Checked toggled back to unchecked")

-- 3. Test Table Formatter
print("\n[Test 3] Table Formatter")
local tbl_buf = vim.api.nvim_create_buf(false, true)
local unformatted_table = {
  "|Col1|Longer Column 2|",
  "|:---|:---|",
  "|a|b|",
}
vim.api.nvim_buf_set_lines(tbl_buf, 0, -1, false, unformatted_table)
vim.api.nvim_set_current_buf(tbl_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local tbl_tool = require("super-markdown.tools.table")
tbl_tool.format()
local formatted_lines = vim.api.nvim_buf_get_lines(tbl_buf, 0, -1, false)
assert_eq(#formatted_lines, 3, "Table should keep 3 lines")
assert_eq(formatted_lines[1], "| Col1 | Longer Column 2 |", "Header row padded correctly")
assert_eq(formatted_lines[3], "| a    | b               |", "Data row aligned to max column width")

-- Test escaped pipes and inline code pipes in Table Formatter & Renderer
local esc_tbl_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(esc_tbl_buf, 0, -1, false, {
  "| Command | Arguments | Description |",
  "| :--- | :--- | :--- |",
  "| **`:SpotlightPick`** | `[jump\\|swap\\|close]` | Trigger picker |",
  "| `:SpotlightDim` | `on` \\| `off` | Toggle dim |",
})
vim.api.nvim_set_current_buf(esc_tbl_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
tbl_tool.format({ bufnr = esc_tbl_buf, silent = true })
local esc_formatted = vim.api.nvim_buf_get_lines(esc_tbl_buf, 0, -1, false)
local tables_render = require("super-markdown.render.tables")
assert_eq(#tables_render.find_unescaped_pipes(esc_formatted[3]), 4, "Escaped/code pipes ignored: exactly 4 column pipes in row 3")
assert_eq(#tables_render.find_unescaped_pipes(esc_formatted[4]), 4, "Escaped pipes ignored: exactly 4 column pipes in row 4")
assert_eq(tables_render.visual_cell_width("**`<leader>wf`**", 2), 10, "Visual cell width strips concealed ** and ` markers")

-- 4. Test Mermaid Block Scanner
print("\n[Test 4] Mermaid Block Scanner")
local mmd_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(mmd_buf, 0, -1, false, {
  "# Intro",
  "```mermaid",
  "graph TD",
  "A --> B",
  "```",
  "End text",
})
local mmd_mod = require("super-markdown.mermaid")
local blocks = mmd_mod.get_blocks(mmd_buf)
assert_eq(#blocks, 1, "Should detect 1 mermaid block")
assert_eq(blocks[1].start_lnum, 2, "Mermaid block start line")
assert_eq(blocks[1].end_lnum, 5, "Mermaid block end line")

-- 5. Test Mermaid ASCII Renderer
print("\n[Test 5] Mermaid ASCII Renderer")
local ascii_mod = require("super-markdown.mermaid.ascii")
local ascii_result = ascii_mod.render("graph TD\nA[Start] --> B[End]")
assert_eq(type(ascii_result), "table", "ASCII result is table of strings")
assert_eq(#ascii_result > 5, true, "ASCII output has rendered lines")

-- 6. Test In-Buffer Extmarks Rendering
print("\n[Test 6] In-Buffer Rendering Pipeline")
local render_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(render_buf, 0, -1, false, {
  "# Heading 1",
  "- [ ] Checkbox",
  "> [!NOTE]",
  "> Callout body",
  "---",
  "| A | B |",
  "|---|---|",
  "| 1 | 2 |",
  "```lua",
  "local x = 1",
  "```",
})
local render_mod = require("super-markdown.render")
local test_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(test_win, render_buf)
render_mod.render(render_buf)
local extmarks = vim.api.nvim_buf_get_extmarks(render_buf, render_mod.get_namespace(), 0, -1, { details = true })
assert_eq(#extmarks > 8, true, "Extmarks populated across elements including codeblock")

-- Verify codeblock line highlighting & left border
local has_code_hl = false
for _, em in ipairs(extmarks) do
  local d = em[4]
  if d.line_hl_group == "SuperMarkdownCodeBlock" then
    has_code_hl = true
    break
  end
end
assert_eq(has_code_hl, true, "Codeblock lines receive background highlight")
assert_eq(vim.api.nvim_get_option_value("concealcursor", { win = test_win }), "nc", "concealcursor defaults to 'nc' to keep normal-mode reading clean and insert-mode editable")

-- 7. Test Telescope TOC Configuration & Preview Scrolling
print("\n[Test 7] Telescope TOC & Preview Scrolling")
local has_telescope, pickers = pcall(require, "telescope.pickers")
if has_telescope then
  local ttoc = require("super-markdown.toc.telescope")
  local orig_new = pickers.new
  local captured_picker = nil
  pickers.new = function(opts, defaults)
    local p = orig_new(opts, defaults)
    captured_picker = p
    return {
      find = function() end,
    }
  end

  vim.api.nvim_set_current_buf(test_buf)
  ttoc.open({})
  pickers.new = orig_new

  assert_eq(captured_picker ~= nil, true, "Telescope picker initialized")
  assert_eq(captured_picker.sorting_strategy, "ascending", "TOC sorting strategy is ascending")
  assert_eq(captured_picker.default_selection_index, 1, "TOC starts at first heading")
  assert_eq(captured_picker.layout_config.prompt_position, "top", "Prompt position is top")

  local previewer = captured_picker.all_previewers[1]
  assert_eq(previewer ~= nil, true, "Telescope previewer attached")

  local pwin = vim.api.nvim_get_current_win()
  local status = { layout = { preview = { winid = pwin } } }
  previewer:preview({ filename = "", bufnr = test_buf, lnum = 3 }, status)
  vim.wait(50, function() return false end)
  assert_eq(vim.api.nvim_win_get_cursor(pwin)[1], 3, "Preview window scrolled to line 3")
else
  print("  (Skipped Telescope test - not installed in environment)")
end

-- 8. Test TOC Sidebar Live Preview & Enter Focus
print("\n[Test 8] TOC Sidebar Live Preview & Enter Focus")
local sidebar = require("super-markdown.toc.sidebar")
local sb_main_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(sb_main_win, test_buf)
vim.api.nvim_win_set_cursor(sb_main_win, { 1, 0 })

sidebar.open()
assert_eq(sidebar.is_open(), true, "Sidebar opened")
local sb_win = vim.api.nvim_get_current_win()
assert_eq(sb_win ~= sb_main_win, true, "Sidebar window is active on open")
assert_eq(vim.api.nvim_win_get_cursor(sb_win)[1], 3, "Sidebar cursor starts on first heading (line 3)")

-- Verify TOC sidebar headings render with exact same markdown heading colors (SuperMarkdownH1..H6)
local sb_buf = vim.api.nvim_win_get_buf(sb_win)
local sb_ns = vim.api.nvim_create_namespace("super_markdown_toc_sidebar")
local sb_marks = vim.api.nvim_buf_get_extmarks(sb_buf, sb_ns, 2, 5, { details = true })
local found_sb_h1 = false
local found_sb_h2 = false
for _, m in ipairs(sb_marks) do
  local hlg = m[4] and m[4].hl_group
  if hlg == "SuperMarkdownH1" then found_sb_h1 = true end
  if hlg == "SuperMarkdownH2" then found_sb_h2 = true end
end
assert_eq(found_sb_h1 and found_sb_h2, true, "TOC sidebar headings render with exact same colors (SuperMarkdownH1, H2) as markdown")

-- Move down to second heading (line 4 in sidebar -> line 3 in test_buf)
vim.api.nvim_win_set_cursor(sb_win, { 4, 0 })
sidebar.preview_heading()
assert_eq(vim.api.nvim_win_get_cursor(sb_main_win)[1], 3, "Main window live preview scrolled to Heading 2 (line 3)")

-- Move down to third heading (line 5 in sidebar -> line 4 in test_buf)
vim.api.nvim_win_set_cursor(sb_win, { 5, 0 })
sidebar.preview_heading()
assert_eq(vim.api.nvim_win_get_cursor(sb_main_win)[1], 4, "Main window live preview scrolled to Heading 3 (line 4)")
assert_eq(vim.api.nvim_get_current_win() == sb_win, true, "Focus remains in sidebar during navigation")

-- Hit Enter
sidebar.jump_to_heading(true)
assert_eq(vim.api.nvim_get_current_win() == sb_main_win, true, "Focus transferred to markdown viewer on Enter")
assert_eq(vim.api.nvim_win_get_cursor(sb_main_win)[1], 4, "Cursor positioned at Heading 3 in markdown viewer")

sidebar.close()
assert_eq(sidebar.is_open(), false, "Sidebar closed cleanly")

-- Test pressing 'q' inside the sidebar quits the sidebar and returns focus to main window
sidebar.open()
assert_eq(sidebar.is_open(), true, "Sidebar re-opened for 'q' quit test")
vim.api.nvim_feedkeys("q", "x", false)
assert_eq(sidebar.is_open(), false, "Pressing 'q' inside sidebar quits the sidebar")
assert_eq(vim.api.nvim_get_current_win(), sb_main_win, "Focus returned to markdown window after pressing 'q'")

-- 9. Test Markdown Folding (+ and - in gutter) & Fold/Unfold All
print("\n[Test 9] Markdown Heading Folding & Gutter Indicators")
local folds_mod = require("super-markdown.folds")
local fold_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(fold_buf, 0, -1, false, {
  "# Section 1",
  "Line 1 content",
  "Line 2 content",
  "## Subsection 1.1",
  "Line 4 content",
  "# Section 2",
  "Line 6 content",
})
local fold_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(fold_win, fold_buf)

-- Test foldexpr calculations (default "toc" mode: every header starts >1 so folding shows all TOC headers)
assert_eq(folds_mod.foldexpr(1), ">1", "H1 starts section fold (>1)")
assert_eq(folds_mod.foldexpr(2), "=", "Body inherits fold level")
assert_eq(folds_mod.foldexpr(4), ">1", "H2 starts independent section fold (>1) so it stays visible in TOC view")
assert_eq(folds_mod.foldexpr(6), ">1", "Next H1 starts section fold (>1)")

-- Attach window options and gutter indicators (+ / -)
folds_mod.attach(fold_buf)
assert_eq(vim.wo[fold_win].foldmethod, "expr", "Foldmethod is set to expr")
assert_eq(vim.wo[fold_win].foldcolumn, "1", "Foldcolumn is enabled in gutter")

local fc = vim.wo[fold_win].fillchars
assert_eq(fc:find("foldopen:%-") ~= nil, true, "Gutter open fold indicator is '-'")
assert_eq(fc:find("foldclose:%+") ~= nil, true, "Gutter closed fold indicator is '+'")

-- Test foldtext formatting with closed folder icon (󰉋)
vim.v.foldstart = 1
vim.v.foldend = 3
local ft_result = folds_mod.foldtext()
assert_eq(type(ft_result), "string", "Foldtext returns string")
assert_eq(ft_result:find("󰉋") ~= nil, true, "Foldtext contains closed folder icon 󰉋")
assert_eq(ft_result:find("Section 1") ~= nil, true, "Foldtext contains section title")
assert_eq(ft_result:find("3 lines") ~= nil, true, "Foldtext displays line count")

-- Test Fold All (zM): all headers (# Section 1, ## Subsection 1.1, # Section 2) remain visible as TOC!
folds_mod.fold_all()
assert_eq(vim.fn.foldclosed(1), 1, "Section 1 (lines 1-3) is folded as its own TOC entry")
assert_eq(vim.fn.foldclosed(4), 4, "Subsection 1.1 (lines 4-5) is folded as its own visible TOC entry")
assert_eq(vim.fn.foldclosed(6), 6, "Section 2 (lines 6-7) is folded as its own visible TOC entry")

-- Test <CR> (handle_normal_enter) unfolding a single section from TOC view and re-folding it
vim.api.nvim_win_set_cursor(fold_win, { 4, 0 })
assert_eq(folds_mod.handle_normal_enter(), true, "<CR> handled on folded header")
assert_eq(vim.fn.foldclosed(4), -1, "Subsection 1.1 unfolded via <CR> while other sections stay folded")
assert_eq(vim.fn.foldclosed(1), 1, "Section 1 remains folded")
assert_eq(folds_mod.handle_normal_enter(), true, "<CR> handled on open header")
assert_eq(vim.fn.foldclosed(4), 4, "Subsection 1.1 folded back into TOC via <CR>")

-- Test Unfold All (zR)
folds_mod.unfold_all()
assert_eq(vim.fn.foldclosed(1), -1, "Section 1 is opened after unfold_all")
assert_eq(vim.fn.foldclosed(4), -1, "Subsection 1.1 is opened after unfold_all")
assert_eq(vim.fn.foldclosed(6), -1, "Section 2 is opened after unfold_all")

-- Test SuperMarkdown fold user commands
vim.cmd("SuperMarkdown fold_all")
assert_eq(vim.fn.foldclosed(1), 1, "SuperMarkdown fold_all command closed folds")
vim.cmd("SuperMarkdown unfold_all")
assert_eq(vim.fn.foldclosed(1), -1, "SuperMarkdown unfold_all command opened folds")

-- 10. Test Mermaid Diagram Syntax Highlighting
print("\n[Test 10] Mermaid Diagram Syntax Highlighting")
local m_syntax = require("super-markdown.mermaid.syntax")

-- Tokenize line tests
local tokens1 = m_syntax.tokenize_line("graph TD")
assert_eq(#tokens1, 2, "2 tokens in 'graph TD'")
assert_eq(tokens1[1][3], "SuperMarkdownMermaidKeyword", "Keyword 'graph' matched")
assert_eq(tokens1[2][3], "SuperMarkdownMermaidType", "Direction 'TD' matched")

local tokens2 = m_syntax.tokenize_line("    Client[Web Client] -->|HTTP| Gateway{API GW}")
local tok_groups = {}
for _, t in ipairs(tokens2) do
  table.insert(tok_groups, t[3])
end
assert_eq(vim.tbl_contains(tok_groups, "SuperMarkdownMermaidNodeId"), true, "NodeId matched")
assert_eq(vim.tbl_contains(tok_groups, "SuperMarkdownMermaidNodeLabel"), true, "NodeLabel matched")
assert_eq(vim.tbl_contains(tok_groups, "SuperMarkdownMermaidArrow"), true, "Arrow matched")
assert_eq(vim.tbl_contains(tok_groups, "SuperMarkdownMermaidEdgeLabel"), true, "EdgeLabel |HTTP| matched")

-- In-Buffer Mermaid Syntax Highlighting test
local m_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(m_buf, 0, -1, false, {
  "# Architecture",
  "```mermaid",
  "graph TD",
  "    A[Start] --> B[End]",
  "```",
})
local m_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(m_win, m_buf)

local sm_render = require("super-markdown.render")
sm_render.render(m_buf)

-- Check extmarks in render namespace
local sm_render = require("super-markdown.render")
local r_ns = sm_render.get_namespace()
local m_marks = vim.api.nvim_buf_get_extmarks(m_buf, r_ns, 0, -1, { details = true })
local found_kw = false
local found_arrow = false
for _, em in ipairs(m_marks) do
  local d = em[4]
  if d.hl_group == "SuperMarkdownMermaidKeyword" then
    found_kw = true
  elseif d.hl_group == "SuperMarkdownMermaidArrow" then
    found_arrow = true
  end
end
assert_eq(found_kw, true, "Mermaid keyword highlighted with extmark in buffer")
assert_eq(found_arrow, true, "Mermaid arrow highlighted with extmark in buffer")

-- 11. Test Spec Analyzer, Task Rollups, Requirement IDs & Traceability
print("\n[Test 11] Spec Analyzer, Rollups & Traceability")
local spec_mod = require("super-markdown.spec")
local spec_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(spec_buf, 0, -1, false, {
  "# Distributed Auth Specification",
  "",
  "> **Document Status**: `DRAFT`",
  "> **Version**: 1.2.0",
  "",
  "## 1. Token Validation",
  "- `@impl: lua/super-markdown/init.lua:1`",
  "- `@test: tests/run_all.lua:1`",
  "- **REQ-01**: Verify HMAC signature in < 5ms.",
  "- [x] Implement JWT parser",
  "- [ ] Add key rotation cache",
  "- [?] Should we support Ed25519 keys in v1?",
  "- [!] Fix timing side-channel in signature check",
  "It should be fast when handling expired tokens.",
})

local analysis = spec_mod.analyze(spec_buf)
assert_eq(analysis.metadata.title, "Distributed Auth Specification", "Parsed spec H1 title")
assert_eq(analysis.metadata.status, "DRAFT", "Parsed spec status metadata")
assert_eq(analysis.metadata.version, "1.2.0", "Parsed spec version metadata")
assert_eq(analysis.totals.checked, 1, "Counted 1 checked task")
assert_eq(analysis.totals.unchecked, 1, "Counted 1 unchecked task")
assert_eq(analysis.totals.question, 1, "Counted 1 open question [?]")
assert_eq(analysis.totals.important, 1, "Counted 1 blocker [!]")
assert_eq(#analysis.reqs, 1, "Extracted REQ-01 requirement")
assert_eq(analysis.reqs[1].id, "REQ-01", "Requirement ID is REQ-01")
assert_eq(analysis.totals.impl_refs, 1, "Extracted 1 @impl reference")
assert_eq(analysis.totals.test_refs, 1, "Extracted 1 @test reference")
assert_eq(analysis.refs[1].exists, true, "@impl reference resolved to existing file")

-- 12. Test Spec Linter (Ambiguity, Questions, Blockers)
print("\n[Test 12] Spec Linter & Diagnostics")
local issues = spec_mod.lint(spec_buf)
assert_eq(#issues >= 3, true, "Linter flagged ambiguous phrase, question, and blocker")
local found_ambiguity = false
for _, iss in ipairs(issues) do
  if iss.kind == "ambiguity" then
    found_ambiguity = true
  end
end
assert_eq(found_ambiguity, true, "Linter detected ambiguous 'should be fast' phrase")

-- 13. Test Spec Status Cycling & Templates
print("\n[Test 13] Spec Status Cycling & Templates")
local next_st = spec_mod.cycle_status(spec_buf)
assert_eq(next_st, "REVIEW", "Cycled status from DRAFT to REVIEW")
local tpl_buf = vim.api.nvim_create_buf(false, true)
spec_mod.new_spec("feature", { bufnr = tpl_buf })
local tpl_lines = vim.api.nvim_buf_get_lines(tpl_buf, 0, -1, false)
assert_eq(#tpl_lines > 20, true, "Inserted feature spec template lines")

-- 14. Test Semantic Spec Picker Items
print("\n[Test 14] Semantic Spec Picker Filtering")
local spec_picker = require("super-markdown.spec.picker")
local q_items = spec_picker.get_items(spec_buf, "question")
assert_eq(#q_items, 1, "Filtered 1 question item")
local b_items = spec_picker.get_items(spec_buf, "blocker")
assert_eq(#b_items, 1, "Filtered 1 blocker item")
local r_items = spec_picker.get_items(spec_buf, "requirement")
assert_eq(#r_items, 1, "Filtered 1 requirement item")

-- 15. Test LLM Context Bundler & Code/Test/Review Prompt Generation
print("\n[Test 15] LLM Context Bundler & Prompt Generators")
local llm_mod = require("super-markdown.llm")
local bundle = llm_mod.bundle_section(spec_buf, 8)
assert_eq(bundle.section_title, "1. Token Validation", "Bundled target section")
assert_eq(#bundle.linked_files, 2, "Bundle includes both @impl and @test linked files")
assert_eq(bundle.linked_files[1].content ~= nil, true, "Linked file content automatically inlined in bundle")
assert_eq(bundle.text:find("<spec_context>") ~= nil, true, "Bundle wrapped in <spec_context> tags")

local code_prompt = llm_mod.build_code_prompt(spec_buf, 8)
assert_eq(code_prompt.text:find("Implement Specification Section") ~= nil, true, "Generated implementation prompt")
assert_eq(code_prompt.tokens > 50, true, "Calculated token estimate for code prompt")

local test_prompt = llm_mod.build_test_prompt(spec_buf, 8)
assert_eq(test_prompt.text:find("Generate Application & Unit Tests") ~= nil, true, "Generated test suite prompt")

local rev_prompt = llm_mod.build_review_prompt(spec_buf, 8)
assert_eq(rev_prompt.text:find("Detected Spec Lint Warnings") ~= nil, true, "Review prompt includes lint warnings")

-- 16. Test Executable Spec Code Block Runner
print("\n[Test 16] Executable Spec Code Block Runner")
local runner_mod = require("super-markdown.tools.runner")
local run_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(run_buf, 0, -1, false, {
  "# Spec Verification",
  "```lua",
  "print('hello from spec')",
  "return 42",
  "```",
})
local run_res = runner_mod.run_block(run_buf, 3)
assert_eq(run_res ~= nil and run_res.ok, true, "Executed inline Lua block cleanly")
assert_eq(run_res.output[1], "hello from spec", "Captured print stdout from block")
assert_eq(run_res.output[2], "=> 42", "Captured return value from block")
local run_marks = vim.api.nvim_buf_get_extmarks(run_buf, runner_mod.get_namespace(), 0, -1, {})
assert_eq(#run_marks, 1, "Rendered virtual lines execution result under code block")

-- 17. Test Smart Code Reference Resolution & Preview Window
print("\n[Test 17] Smart Code Reference & Floating Preview")
local link_mod = require("super-markdown.tools.link")
vim.api.nvim_win_set_buf(0, spec_buf)
vim.api.nvim_win_set_cursor(0, { 7, 5 }) -- line with `- `@impl: lua/super-markdown/init.lua:1``
local ref_at = link_mod.get_reference_at(spec_buf, 7, 5)
assert_eq(ref_at ~= nil and ref_at.kind == "file", true, "Detected @impl reference on line")
assert_eq(ref_at.start_line, 1, "Extracted target line number from reference")
local prev = link_mod.preview()
assert_eq(prev ~= nil and vim.api.nvim_win_is_valid(prev.win), true, "Opened floating reference preview window")
link_mod.close_preview()

-- 18. Test Spec Health Dashboard Window
print("\n[Test 18] Spec Health & Traceability Dashboard")
local dash = spec_mod.dashboard(spec_buf)
assert_eq(dash ~= nil and vim.api.nvim_win_is_valid(dash.win), true, "Opened Spec Health Dashboard window")
spec_mod.close_dashboard()

-- 19. Test Live Read-Only Side Preview Pane (Full Rendering, Mermaid, Tables, Sync)
print("\n[Test 19] Live Read-Only Side Preview Pane")
local preview_pane = require("super-markdown.preview_pane")
local pp_src_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(pp_src_buf, 0, -1, false, {
  "# Live Preview Heading",
  "",
  "Paragraph with **bold text**, `inline_code`, and [Link](https://example.com).",
  "",
  "| Key | Action |",
  "| :--- | :--- |",
  "| **`<leader>mv`** | Toggle `[open\\|close]` |",
  "",
  "```mermaid",
  "graph TD",
  "    Edit[Editor Buffer] --> Preview[Read-Only Preview Pane]",
  "```",
  "",
  "```lua",
  "local function greet(name)",
  "  return 'Hello ' .. name -- greeting",
  "end",
  "```",
  "",
  "- [x] Completed task",
  "- [ ] Pending task",
})
vim.api.nvim_win_set_buf(0, pp_src_buf)
local editor_win = vim.api.nvim_get_current_win()

preview_pane.open({ bufnr = pp_src_buf })
assert_eq(preview_pane.is_open(), true, "Live preview side pane opened")
assert_eq(vim.api.nvim_get_current_win(), editor_win, "Focus stays in editor window when preview opens")

local p_buf = preview_pane.get_buffer()
local p_win = preview_pane.get_window()
assert_eq(vim.bo[p_buf].readonly, true, "Preview buffer is read-only")
assert_eq(vim.bo[p_buf].modifiable, false, "Preview buffer is non-modifiable")

local p_lines = vim.api.nvim_buf_get_lines(p_buf, 0, -1, false)
local joined = table.concat(p_lines, "\n")
assert_eq(joined:find("%*%*") == nil, true, "Raw **bold** syntax markers stripped from preview pane")
assert_eq(joined:find("```mermaid") == nil, true, "Raw ```mermaid fence hidden in preview pane")
assert_eq(joined:find("Editor Buffer") ~= nil, true, "Mermaid diagram rendered directly inside preview pane")
assert_eq(joined:find("┌") ~= nil and joined:find("┘") ~= nil, true, "Table rendered with full Unicode box borders in preview pane")
assert_eq(joined:find("%[open|close%]") ~= nil, true, "Escaped pipe unescaped cleanly in preview pane")

-- Test live sync on edit & cursor move (editor -> preview)
local total_src_lines = vim.api.nvim_buf_line_count(pp_src_buf)
vim.api.nvim_win_set_cursor(editor_win, { total_src_lines, 0 })
preview_pane.sync_scroll()
local p_cursor = vim.api.nvim_win_get_cursor(p_win)[1]
assert_eq(p_cursor > 10, true, "Preview pane scrolled in sync with source cursor")

-- Verify code block syntax highlighting extmarks in preview buffer
local p_extmarks = vim.api.nvim_buf_get_extmarks(p_buf, -1, 0, -1, { details = true })
local has_kw_hl = false
local has_str_hl = false
local has_cmt_hl = false
for _, em in ipairs(p_extmarks) do
  local hl = em[4] and em[4].hl_group
  if hl == "SuperMarkdownMermaidKeyword" then has_kw_hl = true end
  if hl == "SuperMarkdownMermaidString" then has_str_hl = true end
  if hl == "SuperMarkdownMermaidComment" then has_cmt_hl = true end
end
assert_eq(has_kw_hl and has_str_hl and has_cmt_hl, true, "Code block syntax highlighting (keywords, strings, comments) applied in preview pane")

-- Test reverse sync (preview -> editor)
vim.api.nvim_set_current_win(p_win)
vim.api.nvim_win_set_cursor(p_win, { 1, 0 })
preview_pane.sync_from_preview("cursor")
assert_eq(vim.api.nvim_win_get_cursor(editor_win)[1], 1, "Source editor synced with preview pane cursor")

-- Test toggling sync directions (source-only, preview-only, off, both)
preview_pane.set_sync("source")
vim.api.nvim_win_set_cursor(p_win, { #p_lines, 0 })
preview_pane.sync_from_preview("cursor")
assert_eq(vim.api.nvim_win_get_cursor(editor_win)[1], 1, "Reverse sync disabled when sync_from_preview is false")
preview_pane.set_sync("both")

-- Test <CR> / jump_to_source takes focus and cursor back to editable buffer
vim.api.nvim_win_set_cursor(p_win, { #p_lines, 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
assert_eq(vim.api.nvim_get_current_win(), editor_win, "Pressing <CR> in preview pane focuses editable source buffer")
assert_eq(vim.api.nvim_win_get_cursor(editor_win)[1], total_src_lines, "Pressing <CR> in preview pane jumps to matching source line")

-- Test <2-LeftMouse> mapping exists on preview buffer and jumps to editable buffer
local has_dblclick = false
for _, km in ipairs(vim.api.nvim_buf_get_keymap(p_buf, "n")) do
  if km.lhs == "<2-LeftMouse>" then
    has_dblclick = true
    break
  end
end
assert_eq(has_dblclick, true, "Double-click (<2-LeftMouse>) keymap registered on preview pane buffer")

-- Edit source buffer and verify live refresh updates preview buffer
vim.api.nvim_buf_set_lines(pp_src_buf, 0, 1, false, { "# Updated Live Title" })
preview_pane.refresh()
local updated_p_lines = vim.api.nvim_buf_get_lines(p_buf, 0, 2, false)
assert_eq(updated_p_lines[1]:find("Updated Live Title") ~= nil, true, "Preview pane live-updated when source buffer changed")

preview_pane.close()
assert_eq(preview_pane.is_open(), false, "Live preview side pane closed cleanly")

-- 20. Test Mermaid Badge & Diagram Non-Duplication Across Repeated Renders & Reloads
print("\n[Test 20] Mermaid Badge & Diagram Non-Duplication")
local dup_buf = vim.api.nvim_create_buf(false, true)
vim.bo[dup_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(dup_buf, 0, -1, false, {
  "# Mermaid Deduplication Check",
  "```mermaid",
  "graph TD",
  "    A[Start] --> B[End]",
  "```",
})
vim.api.nvim_win_set_buf(0, dup_buf)
for _ = 1, 5 do
  require("super-markdown.render").render(dup_buf)
  require("super-markdown.mermaid").render_inline(dup_buf)
  require("super-markdown.mermaid").render_status(dup_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = dup_buf })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = dup_buf })
end
require("super-markdown").reload()

local r_ns_dup = require("super-markdown.render").get_namespace()
local m_ns_dup = require("super-markdown.mermaid").get_namespace()
local badge_count = 0
local diag_count = 0
for _, ns_check in ipairs({ r_ns_dup, m_ns_dup }) do
  local marks = vim.api.nvim_buf_get_extmarks(dup_buf, ns_check, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    local d = m[4]
    if d.virt_text then
      for _, vt in ipairs(d.virt_text) do
        if vt[1]:find("Live In-Buffer Render", 1, true) then
          badge_count = badge_count + 1
        end
      end
    end
    if d.virt_lines and #d.virt_lines > 3 then
      diag_count = diag_count + 1
    end
  end
end
assert_eq(badge_count, 1, "Exactly 1 [Live In-Buffer Render] badge at start of Mermaid block")
assert_eq(diag_count, 1, "Exactly 1 rendered diagram at end of Mermaid block")

-- 21. Test Markdown Focus Mode (Block, Section & TOC Spotlight & Dimming)
print("\n[Test 21] Markdown Focus Mode (Spotlight Active Block, Dim Others)")
local focus_mod = require("super-markdown.focus")
local f_buf = vim.api.nvim_create_buf(false, true)
vim.bo[f_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(f_buf, 0, -1, false, {
  "# Focus Mode Document",
  "",
  "Paragraph 1 intro text.",
  "",
  "| Col A | Col B |",
  "| :--- | :--- |",
  "| 1 | 2 |",
  "",
  "```lua",
  "local active = true",
  "return active",
  "```",
  "",
  "- [ ] Task 1",
  "- [x] Task 2",
})
vim.api.nvim_win_set_buf(0, f_buf)

-- Test default scope
assert_eq(focus_mod.get_scope(f_buf), "toc", "Focus mode default scope is 'toc'")

-- Test block ranges across document elements
local tbl_s, tbl_e = focus_mod.get_block_range(f_buf, 6, "block")
assert_eq(tbl_s == 5 and tbl_e == 7, true, "Table block range [5..7] detected accurately")

local code_s, code_e = focus_mod.get_block_range(f_buf, 10, "block")
assert_eq(code_s == 9 and code_e == 12, true, "Code block range [9..12] detected accurately")

local list_s, list_e = focus_mod.get_block_range(f_buf, 15, "block")
assert_eq(list_s == 14 and list_e == 15, true, "List block range [14..15] detected accurately")

local p_s, p_e = focus_mod.get_block_range(f_buf, 3, "block")
assert_eq(p_s == 3 and p_e == 3, true, "Paragraph block range [3..3] detected accurately")

-- Test section scope
local sec_s, sec_e = focus_mod.get_block_range(f_buf, 10, "section")
assert_eq(sec_s == 1 and sec_e == 15, true, "Section scope spans from H1 heading to end of section [1..15]")

-- Test TOC scope on showcase.md (first root mentioned in TOC [1..6] highlighted, rest dimmed)
local sc_buf = vim.fn.bufadd("examples/showcase.md")
vim.fn.bufload(sc_buf)
local toc_s1, toc_e1 = focus_mod.get_block_range(sc_buf, 1, "toc")
assert_eq(toc_s1 == 1 and toc_e1 == 6, true, "First root mentioned in TOC spans [1..6] (stops before next TOC heading on line 7)")

local toc_s_intro, toc_e_intro = focus_mod.get_block_range(sc_buf, 3, "toc")
assert_eq(toc_s_intro == 1 and toc_e_intro == 6, true, "Preamble content under first root in TOC also focuses [1..6]")

local toc_s2, toc_e2 = focus_mod.get_block_range(sc_buf, 7, "toc")
assert_eq(toc_s2 == 7 and toc_e2 == 19, true, "Second heading in TOC spans [7..19] (stops before third heading on line 20)")

-- Test toggle focus on/off
assert_eq(focus_mod.is_enabled(f_buf), false, "Focus mode starts disabled by default")
local st_on = focus_mod.toggle(f_buf, "on")
assert_eq(st_on, true, "Focus mode enabled via toggle('on')")
assert_eq(focus_mod.is_enabled(f_buf), true, "is_enabled returns true")

focus_mod.toggle(f_buf, "section")
assert_eq(focus_mod.get_scope(f_buf), "section", "Focus scope switched to 'section'")

focus_mod.toggle(f_buf, "toc")
assert_eq(focus_mod.get_scope(f_buf), "toc", "Focus scope switched back to 'toc'")

local st_off = focus_mod.toggle(f_buf, "off")
assert_eq(st_off, false, "Focus mode disabled via toggle('off')")
assert_eq(focus_mod.is_enabled(f_buf), false, "is_enabled returns false")

-- 22. Test Git Spec Diff & Eyeballer HUD
print("\n[Test 22] Git Spec Diff & Eyeballer HUD")
local diff_mod = require("super-markdown.spec.diff")
local d_buf = vim.api.nvim_create_buf(false, true)
vim.bo[d_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(d_buf, 0, -1, false, {
  "# Spec Under Review",
  "",
  "## 1. Authentication",
  "- [x] Login endpoint",
  "- [ ] Multi-factor authentication",
  "",
  "## 2. API Contract",
  "GET /api/v1/users",
})
vim.api.nvim_win_set_buf(0, d_buf)

local d_hunks, d_stats = diff_mod.compute_diff(d_buf)
assert_eq(type(d_hunks), "table", "compute_diff returns hunks table")
assert_eq(type(d_stats), "table", "compute_diff returns stats table")

local d_sec = diff_mod.get_section_diffs(d_buf)
assert_eq(type(d_sec), "table", "get_section_diffs returns section mapping")

-- Render diff extmarks
diff_mod.render(d_buf)
local d_ns = vim.api.nvim_create_namespace("super_markdown_spec_diff")
assert_eq(type(d_ns), "number", "Diff namespace is valid")
diff_mod.clear(d_buf)
local marks_after_clear = vim.api.nvim_buf_get_extmarks(d_buf, d_ns, 0, -1, {})
assert_eq(#marks_after_clear, 0, "Diff extmarks cleared cleanly")

-- 23. Test Semantic Spec Navigation (Requirements, Questions, Blockers, Tasks)
print("\n[Test 23] Semantic Spec Navigation (Requirements, Questions, Blockers, Tasks)")
local nav_mod = require("super-markdown.spec.navigation")
local nav_buf = vim.api.nvim_create_buf(false, true)
vim.bo[nav_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(nav_buf, 0, -1, false, {
  "# Architecture Spec",
  "",
  "### REQ-01: User Session Management",
  "- [x] JWT verification",
  "- [ ] Refresh token rotation",
  "- [?] Can sessions be invalidated globally?",
  "",
  "> [!CAUTION]",
  "> High memory footprint with in-memory store",
  "",
  "### AC-02: OAuth Provider Integration",
  "- [!] Missing client secret encryption",
})
vim.api.nvim_win_set_buf(0, nav_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

-- Jump next requirement
nav_mod.jump_next_requirement(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 3, "Jumped to first requirement REQ-01 (line 3)")
nav_mod.jump_next_requirement(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 11, "Jumped to second requirement AC-02 (line 11)")
nav_mod.jump_prev_requirement(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 3, "Jumped back to REQ-01 (line 3)")

-- Jump questions
vim.api.nvim_win_set_cursor(0, { 1, 0 })
nav_mod.jump_next_question(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 6, "Jumped to open question [?] on line 6")

-- Jump blockers
vim.api.nvim_win_set_cursor(0, { 1, 0 })
nav_mod.jump_next_blocker(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 8, "Jumped to blocker [!CAUTION] on line 8")

-- Jump pending tasks
vim.api.nvim_win_set_cursor(0, { 1, 0 })
nav_mod.jump_next_task(nav_buf)
assert_eq(vim.api.nvim_win_get_cursor(0)[1], 5, "Jumped to pending task [ ] on line 5")

-- 24. Test Human Review & Breadcrumb HUD
print("\n[Test 24] Human Review & Breadcrumb HUD")
local review_mod = require("super-markdown.spec.review")
local bc_mod = require("super-markdown.render.breadcrumb")

local r_buf = vim.api.nvim_create_buf(false, true)
vim.bo[r_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(r_buf, 0, -1, false, {
  "# Root Spec",
  "## Section A",
  "Some details",
  "### Subsection B",
  "Sub details",
})
vim.api.nvim_win_set_buf(0, r_buf)
vim.api.nvim_win_set_cursor(0, { 4, 0 })

-- Breadcrumb test
local bc_str, bc_chain = bc_mod.get_breadcrumb(r_buf, 4)
assert_eq(#bc_chain >= 2, true, "Breadcrumb chain includes hierarchy")
assert_eq(bc_str:find("Subsection B") ~= nil, true, "Breadcrumb string contains active subsection")

-- Review approve test
vim.api.nvim_win_set_cursor(0, { 2, 0 })
review_mod.review_approve(r_buf)
local r_lines = vim.api.nvim_buf_get_lines(r_buf, 0, 5, false)
local has_approved = false
for _, l in ipairs(r_lines) do
  if l:find("%[!APPROVED%]") then has_approved = true end
end
assert_eq(has_approved, true, "Section approved badge stamped into document")

-- Review question test
vim.api.nvim_win_set_cursor(0, { 4, 0 })
review_mod.review_question(r_buf, "Please verify edge cases")
local q_lines = vim.api.nvim_buf_get_lines(r_buf, 0, -1, false)
local has_agent_q = false
for _, l in ipairs(q_lines) do
  if l:find("@agent: Please verify edge cases") then has_agent_q = true end
end
assert_eq(has_agent_q, true, "Review question directive for AI agent inserted into document")

-- 25. Test Visual Breathing Room, Lists, Key-Value Contrast & Inline Code Pills
print("\n[Test 25] Visual Breathing Room, Lists, Key-Value Contrast & Inline Code Pills")
local dense_buf = vim.api.nvim_create_buf(false, true)
vim.bo[dense_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(dense_buf, 0, -1, false, {
  "# Root Spec",
  "## Section A",
  "- **Namespaces**: Dedicated `super_markdown_render` extmarks.",
  "  - Nested item under namespaces",
  "1. **Ordered Step**: Run `tests/run_all.lua`.",
  "> Standard blockquote vision statement",
})
vim.api.nvim_win_set_buf(0, dense_buf)
local render = require("super-markdown.render")
render.render(dense_buf)
local d_extmarks = vim.api.nvim_buf_get_extmarks(dense_buf, render.get_namespace(), 0, -1, { details = true })
assert_eq(#d_extmarks >= 6, true, "Extmarks placed on headings, lists, inline code, and quotes")

-- Check virtual blank line above H2
local has_h2_spacing = false
for _, em in ipairs(d_extmarks) do
  local d = em[4]
  if em[2] == 1 and d.virt_lines and #d.virt_lines > 0 and d.virt_lines_above then
    has_h2_spacing = true
    break
  end
end
assert_eq(has_h2_spacing, true, "H2 heading received virtual line breathing room above")

-- Check inline code pill styling
local has_code_pill = false
for _, em in ipairs(d_extmarks) do
  local d = em[4]
  if d.hl_group == "SuperMarkdownInlineCode" then
    has_code_pill = true
    break
  end
end
assert_eq(has_code_pill, true, "Inline code `super_markdown_render` received SuperMarkdownInlineCode highlight")

-- Check Key-Value list contrast
local has_list_key = false
for _, em in ipairs(d_extmarks) do
  local d = em[4]
  if d.hl_group == "SuperMarkdownListKey" then
    has_list_key = true
    break
  end
end
assert_eq(has_list_key, true, "List key **Namespaces** received SuperMarkdownListKey contrast highlight")

-- 26. Test Executive Skim / X-Ray Mode (Prose Dimmer)
print("\n[Test 26] Executive Skim / X-Ray Mode")
local skim_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(skim_buf, 0, -1, false, {
  "# Architecture Spec",
  "This is a long verbose paragraph explaining background motivations that humans want to skim past.",
  "- [x] Core task 1",
  "| Col A | Col B |",
  "| :--- | :--- |",
  "| 1 | 2 |",
  "Another wordy prose paragraph generated by the AI agent that can be dimmed.",
})
local skim_mod = require("super-markdown.skim")
assert_eq(skim_mod.is_enabled(skim_buf), false, "Skim mode initially disabled")
skim_mod.enable(skim_buf)
assert_eq(skim_mod.is_enabled(skim_buf), true, "Skim mode enabled")
local skim_marks = vim.api.nvim_buf_get_extmarks(skim_buf, vim.api.nvim_create_namespace("super_markdown_skim"), 0, -1, { details = true })
assert_eq(#skim_marks >= 2, true, "Prose paragraph lines received dimming extmarks in Skim mode")
local found_dimmed = false
for _, em in ipairs(skim_marks) do
  if em[4].hl_group == "SuperMarkdownSkimDimmed" then
    found_dimmed = true
    break
  end
end
assert_eq(found_dimmed, true, "Paragraph prose dimmed with SuperMarkdownSkimDimmed highlight")
skim_mod.disable(skim_buf)
assert_eq(skim_mod.is_enabled(skim_buf), false, "Skim mode disabled and marks cleared")

-- 27. Test AI Boilerplate & Fluff Radar
print("\n[Test 27] AI Boilerplate & Fluff Radar")
local fluff_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(fluff_buf, 0, -1, false, {
  "# Execution Plan",
  "Certainly! Here is the implementation plan for the requested feature:",
  "Without further ado, let's dive into the core architecture.",
  "In this section we will discuss the database indices.",
  "Valid technical specification sentence.",
})
local fluff_mod = require("super-markdown.render.fluff")
local fluff_items = fluff_mod.find_fluff(fluff_buf)
assert_eq(#fluff_items >= 3, true, "Detected 3 AI fluff phrases in agent markdown")
assert_eq(fluff_items[1].line:find("Certainly") ~= nil, true, "Identified 'Certainly!' conversational fluff")

-- 28. Test Critical Risk & Destructive Operation Radar
print("\n[Test 28] Critical Risk & Destructive Operation Radar")
local risk_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(risk_buf, 0, -1, false, {
  "# Migration Guide",
  "Run `rm -rf /var/cache/app` before deploying.",
  "DROP TABLE legacy_users;",
  "token: 'ghp_secrettokenvalue1234567890'",
  "BREAKING CHANGE: All endpoints now require Bearer token.",
})
local risks_mod = require("super-markdown.render.risks")
local risk_items = risks_mod.find_risks(risk_buf)
assert_eq(#risk_items >= 4, true, "Identified 4 critical hazards in agent spec")
local has_destructive, has_secret, has_breaking = false, false, false
for _, r in ipairs(risk_items) do
  if r.kind == "destructive" then has_destructive = true end
  if r.kind == "security" then has_secret = true end
  if r.kind == "breaking" then has_breaking = true end
end
assert_eq(has_destructive, true, "Flagged destructive command (rm -rf / DROP TABLE)")
assert_eq(has_secret, true, "Flagged hardcoded credential / secret")
assert_eq(has_breaking, true, "Flagged breaking change declaration")

-- 29. Test Acceptance Criteria & BDD Scenarios (Given/When/Then, AC-*)
print("\n[Test 29] Acceptance Criteria & BDD Scenarios")
local bdd_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bdd_buf, 0, -1, false, {
  "# Feature Specification",
  "### Scenario: User profile retrieval",
  "- Given a valid session token",
  "- When user calls GET /api/v1/profile",
  "- Then response code should be 200",
  "**AC-01**: Payload must contain user_id and email.",
})
local bdd_mod = require("super-markdown.render.bdd")
local scenarios = bdd_mod.find_scenarios(bdd_buf)
assert_eq(#scenarios >= 3, true, "Extracted BDD scenarios and AC codes")
local render_ns = render.get_namespace()
render.render(bdd_buf)
local bdd_extmarks = vim.api.nvim_buf_get_extmarks(bdd_buf, render_ns, 0, -1, { details = true })
local has_given, has_then = false, false
for _, em in ipairs(bdd_extmarks) do
  local d = em[4]
  if d.virt_text then
    for _, vt in ipairs(d.virt_text) do
      if vt[1]:find("Given") then has_given = true end
      if vt[1]:find("Then") then has_then = true end
    end
  end
end
assert_eq(has_given, true, "Rendered BDD Given pill badge")
assert_eq(has_then, true, "Rendered BDD Then pill badge")

-- 30. Test Expanded Callout Types (APPROVED, REJECTED, AGENT, DECISION, etc.)
print("\n[Test 30] Expanded Callout Types")
local callout_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(callout_buf, 0, -1, false, {
  "> [!APPROVED] Architecture approved by lead on 2026-11-10",
  "> [!REJECTED] Inadequate test coverage",
  "> [!AGENT] Use streaming response parser",
  "> [!DECISION] Adopt SQLite over JSON files",
  "> [!SECURITY] Do not log bearer tokens",
})
render.render(callout_buf)
local callout_marks = vim.api.nvim_buf_get_extmarks(callout_buf, render_ns, 0, -1, { details = true })
local has_appr, has_rej, has_agent, has_sec = false, false, false, false
for _, em in ipairs(callout_marks) do
  local d = em[4]
  if d.virt_text then
    for _, vt in ipairs(d.virt_text) do
      if vt[2] == "SuperMarkdownCalloutApproved" then has_appr = true end
      if vt[2] == "SuperMarkdownCalloutRejected" then has_rej = true end
      if vt[2] == "SuperMarkdownCalloutAgent" then has_agent = true end
      if vt[2] == "SuperMarkdownCalloutSecurity" then has_sec = true end
    end
  end
end
assert_eq(has_appr, true, "Rendered [!APPROVED] with SuperMarkdownCalloutApproved")
assert_eq(has_rej, true, "Rendered [!REJECTED] with SuperMarkdownCalloutRejected")
assert_eq(has_agent, true, "Rendered [!AGENT] with SuperMarkdownCalloutAgent")
assert_eq(has_sec, true, "Rendered [!SECURITY] with SuperMarkdownCalloutSecurity")

-- 31. Test Human Review Workflow & Prompt Export
do
  print("\n[Test 31] Human Review Workflow & Prompt Export")
  local rev_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(rev_buf, 0, -1, false, {
    "# Agent Spec Review Target",
    "> **Document Status**: `DRAFT`",
    "",
    "## 1. Authentication",
    "- [x] Implement OAuth2",
    "- [?] Which token refresh policy to use?",
    "",
    "## 2. Data Storage",
    "- [!] Hardcoded database credentials must be removed",
  })
  local review_mod = require("super-markdown.spec.review")
  vim.api.nvim_win_set_buf(0, rev_buf)
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  review_mod.review_approve(rev_buf)
  local rev_lines = vim.api.nvim_buf_get_lines(rev_buf, 0, -1, false)
  local has_approved_badge = false
  for _, l in ipairs(rev_lines) do
    if l:match("^>%s*%[!APPROVED%]") then has_approved_badge = true break end
  end
  assert_eq(has_approved_badge, true, "Inserted [!APPROVED] section badge")

  -- Add comment
  review_mod.review_comment(rev_buf, "Benchmark numbers look acceptable")
  rev_lines = vim.api.nvim_buf_get_lines(rev_buf, 0, -1, false)
  local has_comment_badge = false
  for _, l in ipairs(rev_lines) do
    if l:match("^>%s*%[!REVIEW%]") then has_comment_badge = true break end
  end
  assert_eq(has_comment_badge, true, "Inserted [!REVIEW] comment directive")

  -- Export agent feedback prompt
  local prompt_output = review_mod.review_export(rev_buf)
  assert_eq(type(prompt_output) == "string", true, "Generated exported review prompt string")
  assert_eq(prompt_output:find("Specification Review") ~= nil, true, "Exported prompt contains review header")
  assert_eq(prompt_output:find("Instructions for AI Agent") ~= nil, true, "Exported prompt contains agent instructions")

  -- Test approve all & reject all
  review_mod.review_approve_all(rev_buf)
  local st_lines = vim.api.nvim_buf_get_lines(rev_buf, 0, 5, false)
  local doc_approved = false
  for _, l in ipairs(st_lines) do
    if l:find("APPROVED") then doc_approved = true break end
  end
  assert_eq(doc_approved, true, "Document status stamped APPROVED via review_approve_all")

  -- 32. Test Interactive Spec Eyeballer & Scorecard HUD
  print("\n[Test 32] Spec Eyeballer & Scorecard HUD")
  local eyeball_mod = require("super-markdown.spec.eyeball")
  assert_eq(eyeball_mod.is_open(), false, "Eyeball HUD initially closed")
  eyeball_mod.open(rev_buf)
  assert_eq(eyeball_mod.is_open(), true, "Eyeball HUD opened successfully")
  eyeball_mod.close()
  assert_eq(eyeball_mod.is_open(), false, "Eyeball HUD closed cleanly")

  -- 33. Test Semantic Spec Navigation Jumps
  print("\n[Test 33] Semantic Spec Navigation Jumps")
  local nav_mod = require("super-markdown.spec.navigation")
  vim.api.nvim_win_set_buf(0, risk_buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  nav_mod.jump_next_risk(risk_buf)
  local cur_risk_line = vim.api.nvim_win_get_cursor(0)[1]
  assert_eq(cur_risk_line > 1, true, "jump_next_risk navigated to first risk line")

  vim.api.nvim_win_set_buf(0, bdd_buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  nav_mod.jump_next_scenario(bdd_buf)
  local cur_scen_line = vim.api.nvim_win_get_cursor(0)[1]
  assert_eq(cur_scen_line > 1, true, "jump_next_scenario navigated to first scenario line")

  -- 34. Test Spec Statusline Component
  print("\n[Test 34] Spec Statusline Component")
  local statusline_mod = require("super-markdown.statusline")
  local st_str = statusline_mod.get_status(rev_buf)
  assert_eq(type(st_str) == "string", true, "Statusline returns formatted string")
  assert_eq(st_str:find("Spec:") ~= nil, true, "Statusline contains 'Spec:' indicator")
  assert_eq(st_str:find("APPROVED") ~= nil, true, "Statusline displays document status")
end

-- 35. Test Cross-View Fold & Collapse Synchronization (Sidebar, Editor & Preview)
do
  print("\n[Test 35] Cross-View Fold & Collapse Synchronization (Sidebar, Editor & Preview)")
  local sync_buf = vim.api.nvim_create_buf(false, true)
  local sync_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(sync_win, sync_buf)
  vim.api.nvim_buf_set_lines(sync_buf, 0, -1, false, {
    "# Architecture Overview",
    "High level system design and microservices.",
    "## Database Architecture",
    "PostgreSQL primary and read replicas.",
    "### Sharding Strategy",
    "Consistent hashing across shard nodes.",
    "## Cache Tier",
    "Redis cluster with eviction policy.",
    "# Deployment & Operations",
    "Kubernetes helm charts and gitops pipelines.",
  })

  local folds_sync = require("super-markdown.folds")
  local pp_sync = require("super-markdown.preview_pane")
  local sb_sync = require("super-markdown.toc.sidebar")

  folds_sync.attach(sync_buf)
  pp_sync.open()
  sb_sync.open()

  local p_win = pp_sync.get_window()
  local sb_win = sb_sync.get_window()

  assert_eq(p_win ~= nil and vim.api.nvim_win_is_valid(p_win), true, "Preview window opened")
  assert_eq(sb_win ~= nil and vim.api.nvim_win_is_valid(sb_win), true, "Sidebar window opened")

  -- 1. Verify tree hierarchy in sidebar
  local sb_items = sb_sync.get_visible_items()
  assert_eq(#sb_items, 5, "Initially 5 headings visible in sidebar")
  assert_eq(sb_items[1].heading.title, "Architecture Overview", "H1 item 1")
  assert_eq(sb_items[1].has_children, true, "H1 has children")
  assert_eq(sb_items[1].descendant_count, 3, "H1 has 3 descendants (Database, Sharding, Cache)")
  assert_eq(sb_items[2].has_children, true, "H2 Database has child Sharding")
  assert_eq(sb_items[2].descendant_count, 1, "H2 Database has 1 descendant")
  assert_eq(sb_items[4].has_children, false, "H2 Cache Tier is leaf")
  assert_eq(sb_items[5].has_children, false, "H1 Deployment is leaf")

  -- 2. Collapse H1 (Architecture Overview) from sidebar
  sb_sync.collapse_header(1)
  assert_eq(sb_sync.is_collapsed(1), true, "Section 1 marked collapsed in sidebar")
  local sb_collapsed_items = sb_sync.get_visible_items()
  assert_eq(#sb_collapsed_items, 2, "Only 2 top headings visible when H1 is collapsed (3 child headings hidden)")
  assert_eq(sb_collapsed_items[1].rendered_line:find("▸") ~= nil, true, "Collapsed header shows ▸ arrow in sidebar")
  assert_eq(sb_collapsed_items[1].rendered_line:find("%+3") ~= nil, true, "Collapsed header shows (+3) hidden count badge in sidebar")

  -- Verify fold synchronized to editor window (sync_win)
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end), 1, "Section 1 folded in editor window")

  -- Verify fold synchronized to preview window (p_win)
  local p_l1 = pp_sync.map_source_to_preview(1)
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l1) end) ~= -1, true, "Section 1 folded in preview window")

  -- 3. Expand H1 (Architecture Overview) from preview window via folds_sync.expand_header
  folds_sync.expand_header(1)
  assert_eq(sb_sync.is_collapsed(1), false, "Section 1 expanded in sidebar")
  local sb_expanded_items = sb_sync.get_visible_items()
  assert_eq(#sb_expanded_items, 5, "All 5 headings visible again in sidebar after expand")
  assert_eq(sb_expanded_items[1].rendered_line:find("▾") ~= nil, true, "Expanded header shows ▾ arrow in sidebar")
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end), -1, "Section 1 unfolded in editor window")
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l1) end), -1, "Section 1 unfolded in preview window")

  -- 4. Collapse All (zM) across all views
  folds_sync.collapse_all()
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end) ~= -1, true, "Editor folded all (zM)")
  local p_l9 = pp_sync.map_source_to_preview(9)
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l1) end) ~= -1, true, "Preview folded Section 1 on zM")
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l9) end) ~= -1, true, "Preview folded Section 2 on zM")
  assert_eq(sb_sync.is_collapsed(1), true, "Sidebar collapsed all (zM)")

  -- 5. Expand All (zR) across all views
  folds_sync.expand_all()
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end), -1, "Editor opened all (zR)")
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l1) end), -1, "Preview opened Section 1 on zR")
  assert_eq(vim.api.nvim_win_call(p_win, function() return vim.fn.foldclosed(p_l9) end), -1, "Preview opened Section 2 on zR")
  assert_eq(sb_sync.is_collapsed(1), false, "Sidebar opened all (zR)")

  -- 6. Toggle Header (za)
  folds_sync.toggle_header(1)
  assert_eq(sb_sync.is_collapsed(1), true, "toggle_header folded Section 1")
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end) ~= -1, true, "Editor folded Section 1 on toggle")
  folds_sync.toggle_header(1)
  assert_eq(sb_sync.is_collapsed(1), false, "toggle_header unfolded Section 1")
  assert_eq(vim.api.nvim_win_call(sync_win, function() return vim.fn.foldclosed(1) end), -1, "Editor unfolded Section 1 on second toggle")

  -- 7. Clean teardown
  sb_sync.close()
  pp_sync.close()
  assert_eq(sb_sync.is_open(), false, "Sidebar closed cleanly after sync tests")
  assert_eq(pp_sync.is_open(), false, "Preview closed cleanly after sync tests")
end

-- 36. Test TOC Sidebar Scroll-to-Top (zt) & Sticky Stacked Headers
do
  print("\n[Test 36] TOC Sidebar Scroll-to-Top (zt) & Sticky Stacked Headers")
  local sticky_mod = require("super-markdown.sticky")
  local st_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st_buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(st_buf, 0, -1, false, {
    "# 1. Core Architecture",     -- L1
    "Overview paragraph 1",       -- L2
    "Overview paragraph 2",       -- L3
    "## 1.1 Cluster Topology",    -- L4
    "Cluster paragraph 1",        -- L5
    "Cluster paragraph 2",        -- L6
    "### 1.1.1 Raft Consensus",   -- L7
    "Raft paragraph 1",           -- L8
    "Raft paragraph 2",           -- L9
    "Raft paragraph 3",           -- L10
    "# 2. Security Model",        -- L11
    "Security paragraph 1",       -- L12
  })
  local st_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(st_win, st_buf)
  vim.api.nvim_win_set_height(st_win, 8)

  local sb_tool = require("super-markdown.toc.sidebar")
  sb_tool.open()
  local sb_tool_win = sb_tool.get_window()
  assert_eq(sb_tool.is_open(), true, "TOC Sidebar opened for scroll-to-top test")

  -- 1. Test scroll_to_top = true positions heading at the very top (zt)
  sb_tool.set_scroll_to_top(true)
  assert_eq(sb_tool.is_scroll_to_top(), true, "scroll_to_top option enabled")

  -- Move sidebar cursor to Heading 2 (Line 4 in markdown, row 4 in sidebar)
  vim.api.nvim_win_set_cursor(sb_tool_win, { 4, 0 })
  sb_tool.preview_heading()
  local st_v1 = vim.api.nvim_win_call(st_win, vim.fn.winsaveview)
  assert_eq(st_v1.topline, 4, "Heading 2 positioned at top of window (topline=4 via zt)")

  -- 2. Toggle scroll_to_top to false (center positioning via zz)
  sb_tool.set_scroll_to_top("toggle")
  assert_eq(sb_tool.is_scroll_to_top(), false, "scroll_to_top toggled to false (center mode)")
  sb_tool.preview_heading()
  local st_v2 = vim.api.nvim_win_call(st_win, vim.fn.winsaveview)
  assert_eq(st_v2.topline < 4, true, "Heading 2 centered (topline < 4 via zz)")

  -- Reset to true
  sb_tool.set_scroll_to_top(true)
  assert_eq(sb_tool.is_scroll_to_top(), true, "scroll_to_top reset to true")

  -- 3. Test Sticky Stacked Headers
  assert_eq(sticky_mod.is_enabled(), false, "Sticky stacked headers initially disabled")
  sticky_mod.enable()
  assert_eq(sticky_mod.is_enabled(), true, "Sticky stacked headers enabled")

  -- Scroll st_win so topline=8 (past Heading 1 at L1, Heading 2 at L4, Heading 3 at L7)
  vim.api.nvim_win_call(st_win, function()
    vim.api.nvim_win_set_cursor(st_win, { 8, 0 })
    vim.cmd("normal! zt")
  end)
  local st_v3 = vim.api.nvim_win_call(st_win, vim.fn.winsaveview)
  assert_eq(st_v3.topline, 8, "Window scrolled past headings to topline=8")

  -- Calculate stacked headers
  local stacked = sticky_mod.get_stacked_headers(st_win)
  assert_eq(#stacked, 3, "3 ancestor headings stacked (H1 Core, H2 Cluster, H3 Raft)")
  assert_eq(stacked[1].title, "1. Core Architecture", "Stacked 1 is H1 Core Architecture")
  assert_eq(stacked[2].title, "1.1 Cluster Topology", "Stacked 2 is H2 Cluster Topology")
  assert_eq(stacked[3].title, "1.1.1 Raft Consensus", "Stacked 3 is H3 Raft Consensus")

  -- Update window and verify floating window
  sticky_mod.update_win(st_win)
  local fwin = sticky_mod.get_float_win(st_win)
  assert_eq(fwin ~= nil and vim.api.nvim_win_is_valid(fwin), true, "Sticky header float is active")
  local fbuf = vim.api.nvim_win_get_buf(fwin)
  local flines = vim.api.nvim_buf_get_lines(fbuf, 0, -1, false)
  assert_eq(#flines, 3, "Floating window renders 3 stacked header lines")
  assert_eq(flines[1]:find("Core Architecture") ~= nil, true, "Float line 1 contains H1 title")
  assert_eq(flines[2]:find("Cluster Topology") ~= nil, true, "Float line 2 contains H2 title")
  assert_eq(flines[3]:find("Raft Consensus") ~= nil, true, "Float line 3 contains H3 title")

  -- 4. Scroll back to top: floating window should automatically close
  vim.api.nvim_win_call(st_win, function()
    vim.api.nvim_win_set_cursor(st_win, { 1, 0 })
    vim.cmd("normal! zt")
  end)
  sticky_mod.update_win(st_win)
  local fwin_closed = sticky_mod.get_float_win(st_win)
  assert_eq(fwin_closed == nil, true, "Sticky header float hides when scrolled back to top")

  -- 5. Toggle & disable sticky headers
  sticky_mod.disable()
  assert_eq(sticky_mod.is_enabled(), false, "Sticky stacked headers disabled")

  sb_tool.close()
  assert_eq(sb_tool.is_open(), false, "TOC Sidebar closed cleanly")
end

-- =========================================================================
-- Test 37: Dynamic Document Focus & Deep Hierarchy Progressive Folding (zm/zr)
-- =========================================================================
do
  print("\n[Test 37] Dynamic Document Focus & Deep Hierarchy Progressive Folding (zm/zr)")

  local sb_tool = require("super-markdown.toc.sidebar")
  local folds_mod = require("super-markdown.folds")

  -- 1. Create two separate markdown documents
  local doc1_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[doc1_buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(doc1_buf, "/tmp/doc_alpha.md")
  vim.api.nvim_buf_set_lines(doc1_buf, 0, -1, false, {
    "# Document Alpha",
    "Alpha intro",
    "## Alpha Section 1",
    "Alpha sec 1 content",
    "### Alpha Detail 1",
    "Alpha detail content",
  })

  local doc2_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[doc2_buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(doc2_buf, "/tmp/doc_beta.md")
  vim.api.nvim_buf_set_lines(doc2_buf, 0, -1, false, {
    "# Document Beta",
    "Beta intro",
    "## Beta Section 1",
    "Beta sec 1 content",
    "### Beta Detail 1",
    "Beta detail content",
    "## Beta Section 2",
    "Beta sec 2 content",
  })

  local test_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(test_win, doc1_buf)

  -- Open sidebar on Document Alpha
  sb_tool.open()
  assert_eq(sb_tool.is_open(), true, "Sidebar opened on doc1")
  assert_eq(sb_tool.get_source_buf(), doc1_buf, "Sidebar tracking doc1_buf")
  local h1 = sb_tool.get_headings_cache()
  assert_eq(#h1, 3, "Doc1 has 3 headings")
  assert_eq(h1[1].title, "Document Alpha", "Doc1 heading title is Document Alpha")

  -- 2. Simulate switching focus to Document Beta (BufEnter / WinEnter)
  vim.api.nvim_win_set_buf(test_win, doc2_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = doc2_buf })

  assert_eq(sb_tool.get_source_buf(), doc2_buf, "Sidebar dynamically switched to doc2_buf on BufEnter")
  local h2 = sb_tool.get_headings_cache()
  assert_eq(#h2, 4, "Doc2 has 4 headings")
  assert_eq(h2[1].title, "Document Beta", "Doc2 heading title is Document Beta")

  -- Check sidebar rendered lines
  local sbuf = sb_tool.get_buf()
  local slines = vim.api.nvim_buf_get_lines(sbuf, 0, -1, false)
  local found_beta = false
  for _, l in ipairs(slines) do
    if l:find("Document Beta") then found_beta = true end
  end
  assert_eq(found_beta, true, "Sidebar buffer rendered Document Beta content")

  -- 3. Switch back to Document Alpha
  vim.api.nvim_win_set_buf(test_win, doc1_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = doc1_buf })

  assert_eq(sb_tool.get_source_buf(), doc1_buf, "Sidebar dynamically switched back to doc1_buf")
  local h1_back = sb_tool.get_headings_cache()
  assert_eq(h1_back[1].title, "Document Alpha", "Doc1 heading title restored to Document Alpha")

  -- 4. Test per-buffer collapsed state isolation
  -- Collapse Alpha Section 1 (lnum = 3) in Doc1
  sb_tool.set_collapsed(3, true)
  assert_eq(sb_tool.is_collapsed(3), true, "Doc1 heading at lnum=3 collapsed")
  sb_tool.refresh()
  assert_eq(#sb_tool.get_visible_items(), 2, "Doc1 visible items reduced from 3 to 2 (child collapsed)")

  -- Switch to Doc2: lnum=3 should NOT be collapsed in Doc2
  vim.api.nvim_win_set_buf(test_win, doc2_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = doc2_buf })
  assert_eq(sb_tool.is_collapsed(3), false, "Doc2 lnum=3 is NOT collapsed (state isolated per buffer)")
  assert_eq(#sb_tool.get_visible_items(), 4, "Doc2 shows all 4 headings")

  -- Switch back to Doc1: lnum=3 should still be collapsed in Doc1
  vim.api.nvim_win_set_buf(test_win, doc1_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = doc1_buf })
  assert_eq(sb_tool.is_collapsed(3), true, "Doc1 lnum=3 is still collapsed upon return")
  assert_eq(#sb_tool.get_visible_items(), 2, "Doc1 retains collapsed state (2 visible items)")

  -- 5. Deep 6-Level Hierarchy Progressive Folding (zm / zr)
  local deep_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[deep_buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(deep_buf, "/tmp/doc_deep.md")
  vim.api.nvim_buf_set_lines(deep_buf, 0, -1, false, {
    "# Level 1 System Architecture",
    "## Level 2 Agent Cluster",
    "### Level 3 Consensus Engine",
    "#### Level 4 Raft Election",
    "##### Level 5 Heartbeat Lease",
    "###### Level 6 Heartbeat Tick Constraints",
    "###### Level 6 Quorum Split-Brain Rules",
    "##### Level 5 Log Pipeline",
    "###### Level 6 Sharding Policy",
    "#### Level 4 Vector Indexing",
    "##### Level 5 HNSW Optimization",
    "###### Level 6 SIMD Alignment",
  })
  vim.api.nvim_win_set_buf(test_win, deep_buf)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = deep_buf })

  assert_eq(sb_tool.get_source_buf(), deep_buf, "Sidebar switched to deep_buf")
  folds_mod.expand_all()
  local initial_visible = #sb_tool.get_visible_items()
  assert_eq(initial_visible, 12, "Deep document has 12 visible headings initially")

  -- Fold more (zm): collapses deepest headings (level 5, hiding level 6 items)
  folds_mod.fold_more()
  local vis_after_zm1 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zm1 < initial_visible, true, "First zm collapsed level 5 parents, hiding level 6 items")

  -- Fold more (zm): collapses level 4 parents
  folds_mod.fold_more()
  local vis_after_zm2 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zm2 < vis_after_zm1, true, "Second zm collapsed level 4 parents")

  -- Fold more (zm): collapses level 3 parents
  folds_mod.fold_more()
  local vis_after_zm3 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zm3 < vis_after_zm2, true, "Third zm collapsed level 3 parents")

  -- Fold less (zr): unfolds shallowest collapsed level (level 3)
  folds_mod.fold_less()
  local vis_after_zr1 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zr1 > vis_after_zm3, true, "First zr unfolded level 3 parents")

  -- Fold less (zr): unfolds level 4
  folds_mod.fold_less()
  local vis_after_zr2 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zr2 > vis_after_zr1, true, "Second zr unfolded level 4 parents")

  -- Fold less (zr): unfolds level 5
  folds_mod.fold_less()
  local vis_after_zr3 = #sb_tool.get_visible_items()
  assert_eq(vis_after_zr3 > vis_after_zr2, true, "Third zr unfolded level 5 parents")

  -- Expand all (zR): restores all 12 items
  folds_mod.expand_all()
  assert_eq(#sb_tool.get_visible_items(), 12, "zR expanded all 12 headings across views")

  -- Collapse all (zM): collapses everything down to root headers with children
  folds_mod.collapse_all()
  assert_eq(#sb_tool.get_visible_items() < 12, true, "zM collapsed all expandable headings")

  -- Clean up
  sb_tool.close()
  assert_eq(sb_tool.is_open(), false, "Sidebar closed cleanly after Test 37")
end

-- =========================================================================
-- Test 38: Multi-Tab & Multi-Buffer Independent Preview & Sidebar Tying
-- =========================================================================
do
  print("\n[Test 38] Multi-Tab & Multi-Buffer Independent Preview & Sidebar Tying")

  local sb_tool = require("super-markdown.toc.sidebar")
  local pp_tool = require("super-markdown.preview_pane")

  -- Create Document A and Document B
  local doc_a = vim.api.nvim_create_buf(false, true)
  vim.bo[doc_a].filetype = "markdown"
  vim.api.nvim_buf_set_name(doc_a, "/tmp/doc_tab_a.md")
  vim.api.nvim_buf_set_lines(doc_a, 0, -1, false, {
    "# Doc A in Tab 1",
    "Content of Doc A",
    "## Section A.1",
    "Details of Section A.1",
  })

  local doc_b = vim.api.nvim_create_buf(false, true)
  vim.bo[doc_b].filetype = "markdown"
  vim.api.nvim_buf_set_name(doc_b, "/tmp/doc_tab_b.md")
  vim.api.nvim_buf_set_lines(doc_b, 0, -1, false, {
    "# Doc B in Tab 2",
    "Content of Doc B",
    "## Section B.1",
    "Details of Section B.1",
  })

  -- In Tab 1: set doc_a and open preview & sidebar
  local tab1 = vim.api.nvim_get_current_tabpage()
  local win1 = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win1, doc_a)

  pp_tool.open({ bufnr = doc_a })
  sb_tool.open({ focus_sidebar = false })

  assert_eq(pp_tool.is_open(), true, "Tab 1: Preview pane open")
  assert_eq(sb_tool.is_open(), true, "Tab 1: TOC sidebar open")
  assert_eq(pp_tool.get_source_buf(), doc_a, "Tab 1: Preview pane source is doc_a")
  assert_eq(sb_tool.get_source_buf(), doc_a, "Tab 1: Sidebar source is doc_a")

  -- 1. Create a new Tab 2
  vim.cmd("tabnew")
  local tab2 = vim.api.nvim_get_current_tabpage()
  local win2 = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win2, doc_b)
  assert_eq(tab1 ~= tab2, true, "New tabpage created")

  -- In Tab 2: initially neither preview nor sidebar is open in this tabpage
  assert_eq(pp_tool.is_open(), false, "Tab 2: Preview pane is not yet open in new tabpage")
  assert_eq(sb_tool.is_open(), false, "Tab 2: Sidebar is not yet open in new tabpage")

  -- Open preview & sidebar for doc_b in Tab 2
  pp_tool.open({ bufnr = doc_b })
  sb_tool.open({ focus_sidebar = false })

  assert_eq(pp_tool.is_open(), true, "Tab 2: Preview pane now open in Tab 2")
  assert_eq(sb_tool.is_open(), true, "Tab 2: Sidebar now open in Tab 2")
  assert_eq(pp_tool.get_source_buf(), doc_b, "Tab 2: Preview pane tied to doc_b")
  assert_eq(sb_tool.get_source_buf(), doc_b, "Tab 2: Sidebar tied to doc_b")

  -- 2. Switch back to Tab 1
  vim.cmd("tabnext 1")
  assert_eq(vim.api.nvim_get_current_tabpage(), tab1, "Switched back to Tab 1")
  assert_eq(pp_tool.is_open(), true, "Tab 1: Preview pane still open in Tab 1")
  assert_eq(sb_tool.is_open(), true, "Tab 1: Sidebar still open in Tab 1")
  assert_eq(pp_tool.get_source_buf(), doc_a, "Tab 1: Preview pane still tied to doc_a")
  assert_eq(sb_tool.get_source_buf(), doc_a, "Tab 1: Sidebar still tied to doc_a")

  -- 3. Switch to Tab 2 and close Tab 2
  vim.cmd("tabnext 2")
  assert_eq(vim.api.nvim_get_current_tabpage(), tab2, "Switched back to Tab 2")
  pp_tool.close()
  sb_tool.close()
  vim.cmd("tabclose")
  assert_eq(vim.api.nvim_get_current_tabpage(), tab1, "Tab 2 closed, back in Tab 1")
  vim.api.nvim_set_current_win(win1)

  -- 4. Test smart toggle in same tab:
  -- In Tab 1, switch buffer in win1 to doc_b
  vim.api.nvim_win_set_buf(win1, doc_b)
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = doc_b })

  assert_eq(pp_tool.get_source_buf(), doc_b, "Preview pane automatically switched source to doc_b on BufEnter")
  assert_eq(sb_tool.get_source_buf(), doc_b, "Sidebar automatically switched source to doc_b on BufEnter")

  -- Calling toggle while preview is showing doc_b: closes preview
  pp_tool.toggle()
  assert_eq(pp_tool.is_open(), false, "Preview toggled closed")

  -- Calling toggle while sidebar is showing doc_b: closes sidebar
  sb_tool.toggle()
  assert_eq(sb_tool.is_open(), false, "Sidebar toggled closed")
end

-- 39. Test Termaid Integration & Mermaid Renderer Options
do
  print("\n[Test 39] Termaid Integration & Mermaid Renderer Options")
  local termaid_mod = require("super-markdown.mermaid.termaid")
  local mermaid_mod = require("super-markdown.mermaid")
  local sm_main = require("super-markdown")

  assert_eq(type(termaid_mod.is_available), "function", "termaid.is_available is a function")
  assert_eq(type(termaid_mod.render), "function", "termaid.render is a function")

  local avail = termaid_mod.is_available()
  assert_eq(avail, true, "Termaid CLI is detected and available on machine")

  -- Test styled-json rendering with termaid
  local code = "graph TD\n  Start[Start Node] --> Finish[Finish Node]\n"
  local ok, res = termaid_mod.render(code, { padding_x = 2, padding_y = 1, gap = 2 })
  assert_eq(ok, true, "Termaid renders simple graph successfully")
  assert_eq(res.is_styled, true, "Termaid returns styled output")
  assert_eq(#res.text_lines >= 4, true, "Termaid produced multiple text lines")
  assert_eq(#res.virt_lines, #res.text_lines, "Termaid virt_lines count matches text_lines count")

  -- Test active renderer detection and switching
  sm_main.set_mermaid_renderer("internal")
  assert_eq(mermaid_mod.get_active_renderer(), "internal", "Switched renderer to internal")

  sm_main.set_mermaid_renderer("termaid")
  assert_eq(mermaid_mod.get_active_renderer(), "termaid", "Switched renderer to termaid")

  sm_main.set_mermaid_renderer("auto")
  assert_eq(mermaid_mod.get_active_renderer(), "termaid", "Auto prefers termaid when available")

  -- Test in-buffer inline rendering with termaid
  local t_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(t_buf, 0, -1, false, {
    "# Architecture",
    "```mermaid",
    "graph LR",
    "    A[Service A] --> B[Service B]",
    "```",
  })
  mermaid_mod.render_inline(t_buf)
  local t_extmarks = vim.api.nvim_buf_get_extmarks(t_buf, mermaid_mod.get_namespace(), 0, -1, { details = true })
  assert_eq(#t_extmarks >= 2, true, "Extmarks placed for inline diagram and fence banner using termaid")
end

-- 40. Test Upgraded Multi-Branch Horizontal (LR) ASCII Renderer
do
  print("\n[Test 40] Upgraded Multi-Branch Horizontal (LR) ASCII Renderer")
  local ascii_mod = require("super-markdown.mermaid.ascii")
  local lr_sample = [[graph LR
    Client --> API --> DB
    API --> Cache
]]
  local rendered = ascii_mod.render(lr_sample)
  local joined = table.concat(rendered, "\n")
  assert_eq(joined:find("LR - Live", 1, true) ~= nil, true, "Diagram has LR title")
  assert_eq(joined:find("Client") ~= nil, true, "Client node rendered")
  assert_eq(joined:find("API") ~= nil, true, "API node rendered")
  assert_eq(joined:find("DB") ~= nil, true, "DB node rendered")
  assert_eq(joined:find("Cache") ~= nil, true, "Cache node rendered")
  -- Verify horizontal arrow indicators
  assert_eq(joined:find("►") ~= nil or joined:find("▶") ~= nil, true, "Contains horizontal arrowhead ►")
  assert_eq(joined:find("┬") ~= nil, true, "Contains branch T-junction ┬ for multi-target split")
end

print(string.format("\n=== Test Results: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
