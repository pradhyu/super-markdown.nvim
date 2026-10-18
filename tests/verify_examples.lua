-- Automated verification script for super-markdown.nvim examples
vim.opt.runtimepath:prepend(vim.fn.expand("~/git/super-markdown.nvim"))
vim.opt.swapfile = false
vim.opt.shortmess:append("A")

local sm = require("super-markdown")
sm.setup({})

local render = require("super-markdown.render")
local mermaid = require("super-markdown.mermaid")
local compiler = require("super-markdown.mermaid.compiler")
local ascii = require("super-markdown.mermaid.ascii")
local toc = require("super-markdown.toc")
local table_tool = require("super-markdown.tools.table")
local cb_tool = require("super-markdown.tools.checkbox")

local examples = {
  "showcase.md",
  "system_architecture.md",
  "sprint_backlog.md",
  "api_reference.md",
}

local base_dir = vim.fn.expand("~/git/super-markdown.nvim/examples")

print("================================================================")
print("     super-markdown.nvim Comprehensive Verification Suite       ")
print("================================================================")

local total_checks = 0
local passed_checks = 0

local function check(condition, desc)
  total_checks = total_checks + 1
  if condition then
    passed_checks = passed_checks + 1
    print(string.format("  [PASS] %s", desc))
  else
    print(string.format("  [FAIL] %s", desc))
  end
end

-- 1. Test In-Buffer Rendering across all example files
print("\n--- 1. In-Buffer Rendering Verification ---")
for _, fname in ipairs(examples) do
  local full_path = base_dir .. "/" .. fname
  local buf = vim.fn.bufadd(full_path)
  vim.fn.bufload(buf)

  render.render(buf)
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, render.get_namespace(), 0, -1, { details = true })
  
  check(#extmarks > 10, string.format("%s: Rendered with %d active extmarks", fname, #extmarks))
  check(render.is_enabled(buf) == true, string.format("%s: Render state is active", fname))
end

-- 2. Test TOC Extraction and Hierarchy across all example files
print("\n--- 2. Table of Contents & Telescope Hierarchy Verification ---")
for _, fname in ipairs(examples) do
  local full_path = base_dir .. "/" .. fname
  local buf = vim.fn.bufadd(full_path)
  local headings = toc.get_headings(buf)

  check(#headings >= 4, string.format("%s: Found %d structured headings", fname, #headings))
  
  -- Verify hierarchy: level 1 exists, titles are non-empty
  local has_h1 = false
  for _, h in ipairs(headings) do
    if h.level == 1 then has_h1 = true end
    assert(h.title and #h.title > 0, "Heading title should not be empty")
    assert(h.lnum > 0, "Heading line number must be valid")
  end
  check(has_h1, string.format("%s: Contains root H1 heading", fname))
end

-- 3. Test Table Auto-Formatting on api_reference.md
print("\n--- 3. Table Formatter & Alignment Verification ---")
local api_buf = vim.fn.bufadd(base_dir .. "/api_reference.md")
vim.fn.bufload(api_buf)
vim.api.nvim_set_current_buf(api_buf)

-- Place cursor on line 35 (the table row)
local lines = vim.api.nvim_buf_get_lines(api_buf, 0, -1, false)
local table_line_idx = nil
for idx, l in ipairs(lines) do
  if l:match("^|POST|/v1/charges|") then
    table_line_idx = idx
    break
  end
end

check(table_line_idx ~= nil, "Found unaligned table in api_reference.md")
if table_line_idx then
  vim.api.nvim_win_set_cursor(0, { table_line_idx, 5 })
  table_tool.format()

  local new_lines = vim.api.nvim_buf_get_lines(api_buf, 0, -1, false)
  local formatted_row = new_lines[table_line_idx]
  check(formatted_row:find("| POST ") ~= nil, "Table row padded and aligned with spaces")
  check(new_lines[table_line_idx - 1]:find("| :---") ~= nil or new_lines[table_line_idx - 2]:find("| :---") ~= nil, "Alignment markers preserved")
end

-- 4. Test Checkbox Toggle & Cycling
print("\n--- 4. Checkbox Toggle & Multi-State Cycling ---")
local test_cb_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(test_cb_buf, 0, -1, false, { "- [ ] Deploy release" })
vim.api.nvim_set_current_buf(test_cb_buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

-- Toggle
cb_tool.toggle(false)
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [x] Deploy release", "Toggle [ ] -> [x]")

cb_tool.toggle(false)
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [ ] Deploy release", "Toggle [x] -> [ ]")

-- Cycle: [ ] -> [x] -> [-] -> [/] -> [ ]
cb_tool.toggle(true) -- to x
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [x] Deploy release", "Cycle to [x]")
cb_tool.toggle(true) -- to -
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [-] Deploy release", "Cycle to [-]")
cb_tool.toggle(true) -- to /
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [/] Deploy release", "Cycle to [/]")
cb_tool.toggle(true) -- to space
check(vim.api.nvim_buf_get_lines(test_cb_buf, 0, 1, false)[1] == "- [ ] Deploy release", "Cycle back to [ ]")

-- 5. Test Mermaid Extraction & Compilation on all diagrams
print("\n--- 5. Mermaid Diagram Extraction & Compilation Verification ---")
local all_blocks = {}
for _, fname in ipairs(examples) do
  local full_path = base_dir .. "/" .. fname
  local buf = vim.fn.bufadd(full_path)
  local blocks = mermaid.get_blocks(buf)
  for _, b in ipairs(blocks) do
    b.file = fname
    table.insert(all_blocks, b)
  end
end

check(#all_blocks >= 4, string.format("Detected %d Mermaid diagram blocks across examples", #all_blocks))

local pending_compilations = #all_blocks
for idx, b in ipairs(all_blocks) do
  -- Test ASCII representation
  local ascii_out = ascii.render(b.code)
  check(#ascii_out >= 3, string.format("[%s Diagram #%d] ASCII fallback rendered (%d lines)", b.file, idx, #ascii_out))

  -- Test compiler
  compiler.compile(b.code, function(err, res)
    pending_compilations = pending_compilations - 1
    if err then
      check(res.ascii ~= nil and #res.ascii > 0, string.format("[%s Diagram #%d] Handled network/offline gracefully with ASCII fallback (%s)", b.file, idx, err))
    else
      check(res.png ~= nil and vim.fn.filereadable(res.png) == 1, string.format("[%s Diagram #%d] PNG generated and cached: %s", b.file, idx, vim.fs.basename(res.png)))
    end

    if pending_compilations == 0 then
      print("\n================================================================")
      print(string.format("   Verification Complete: %d Passed, %d Failed (Total: %d)", passed_checks, total_checks - passed_checks, total_checks))
      print("================================================================")
      if total_checks == passed_checks then
        vim.cmd("qall!")
      else
        vim.cmd("cquit 1")
      end
    end
  end)
end
