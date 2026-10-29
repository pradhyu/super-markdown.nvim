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
assert_eq(vim.api.nvim_get_option_value("concealcursor", { win = test_win }), "c", "concealcursor defaults to 'c' to keep fences editable")

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

print(string.format("\n=== Test Results: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
