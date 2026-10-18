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

-- Test foldexpr calculations
assert_eq(folds_mod.foldexpr(1), ">1", "H1 starts fold level 1")
assert_eq(folds_mod.foldexpr(2), "=", "Body inherits fold level")
assert_eq(folds_mod.foldexpr(4), ">2", "H2 starts fold level 2")
assert_eq(folds_mod.foldexpr(6), ">1", "Next H1 starts fold level 1")

-- Attach window options and gutter indicators (+ / -)
folds_mod.attach(fold_buf)
assert_eq(vim.wo[fold_win].foldmethod, "expr", "Foldmethod is set to expr")
assert_eq(vim.wo[fold_win].foldcolumn, "1", "Foldcolumn is enabled in gutter")

local fc = vim.wo[fold_win].fillchars
assert_eq(fc:find("foldopen:%-") ~= nil, true, "Gutter open fold indicator is '-'")
assert_eq(fc:find("foldclose:%+") ~= nil, true, "Gutter closed fold indicator is '+'")

-- Test foldtext formatting
vim.v.foldstart = 1
vim.v.foldend = 5
local ft_result = folds_mod.foldtext()
assert_eq(type(ft_result), "string", "Foldtext returns string")
assert_eq(ft_result:find("Section 1") ~= nil, true, "Foldtext contains section title")
assert_eq(ft_result:find("5 lines") ~= nil, true, "Foldtext displays line count")

-- Test Fold All (zM)
folds_mod.fold_all()
assert_eq(vim.fn.foldclosed(1), 1, "Section 1 is closed after fold_all")
assert_eq(vim.fn.foldclosed(6), 6, "Section 2 is closed after fold_all")

-- Test Unfold All (zR)
folds_mod.unfold_all()
assert_eq(vim.fn.foldclosed(1), -1, "Section 1 is opened after unfold_all")
assert_eq(vim.fn.foldclosed(6), -1, "Section 2 is opened after unfold_all")

-- Test SuperMarkdown fold user commands
vim.cmd("SuperMarkdown fold_all")
assert_eq(vim.fn.foldclosed(1), 1, "SuperMarkdown fold_all command closed folds")
vim.cmd("SuperMarkdown unfold_all")
assert_eq(vim.fn.foldclosed(1), -1, "SuperMarkdown unfold_all command opened folds")

print(string.format("\n=== Test Results: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
