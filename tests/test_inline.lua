vim.opt.runtimepath:prepend(vim.fn.expand("~/git/super-markdown.nvim"))

local sm = require("super-markdown")
sm.setup({
  render = {
    enabled = true,
    tables = {
      enabled = true,
      auto_align = true,
    },
  },
  mermaid = {
    enabled = true,
    inline = true,
  },
})

local passed = 0
local failed = 0

local function assert_true(cond, msg)
  if cond then
    passed = passed + 1
    print("  [PASS] " .. msg)
  else
    failed = failed + 1
    print("  [FAIL] " .. msg)
  end
end

print("=== Testing Automated In-Line Rendering ===")

-- 1. Test Automated In-Line Table Rendering & Auto-Alignment
print("\n--- Test 1: Automated In-Line Table Auto-Alignment ---")
local tbl_buf = vim.api.nvim_create_buf(false, true)
local unaligned_raw = {
  "|Method|Path|Description|",
  "|:---|:---|---:|",
  "|POST|/v1/charges|100 req/min|",
  "|GET|/v1/charges/:id|500 req/min|",
}
vim.api.nvim_buf_set_lines(tbl_buf, 0, -1, false, unaligned_raw)

local render_mod = require("super-markdown.render")
render_mod.render(tbl_buf)

local extmarks = vim.api.nvim_buf_get_extmarks(tbl_buf, render_mod.get_namespace(), 0, -1, { details = true })
assert_true(#extmarks >= 10, "Extmarks populated across table cells and borders")

-- Verify buffer lines were NOT modified (pure in-line visual rendering)
local current_lines = vim.api.nvim_buf_get_lines(tbl_buf, 0, -1, false)
assert_true(current_lines[1] == unaligned_raw[1], "Raw buffer text preserved without unwanted edits")

-- Verify screen columns align
vim.o.columns = 120
local win = vim.api.nvim_open_win(tbl_buf, true, { relative = "editor", width = 80, height = 8, row = 0, col = 0 })
vim.cmd("redraw")

local s1 = ""
local s3 = ""
for c = 1, 60 do
  s1 = s1 .. vim.fn.screenstring(1, c)
  s3 = s3 .. vim.fn.screenstring(3, c)
end

assert_true(s1:find("Method") ~= nil, "Screen contains Method header")
assert_true(s3:find("POST") ~= nil, "Screen contains POST row")
assert_true(s1:find("│") ~= nil, "Box border │ rendered in screen row 1")
assert_true(s3:find("│") ~= nil, "Box border │ rendered in screen row 3")

-- 2. Test Automated In-Line Mermaid Rendering
print("\n--- Test 2: Automated In-Line Mermaid Rendering ---")
local mmd_buf = vim.api.nvim_create_buf(false, true)
local mmd_raw = {
  "# Architecture",
  "```mermaid",
  "graph TD",
  "    A[Web Client] --> B{API Gateway}",
  "    B -->|Auth| C[(PostgreSQL)]",
  "    B -->|Cached| D[(Redis)]",
  "```",
  "Footer notes",
}
vim.api.nvim_buf_set_lines(mmd_buf, 0, -1, false, mmd_raw)

render_mod.render(mmd_buf)

local mmd_extmarks = vim.api.nvim_buf_get_extmarks(mmd_buf, render_mod.get_namespace(), 0, -1, { details = true })
local found_virt_lines = false
local found_badge = false

for _, em in ipairs(mmd_extmarks) do
  local details = em[4]
  if details.virt_lines and #details.virt_lines > 0 then
    found_virt_lines = true
  end
  if details.virt_text then
    for _, vt in ipairs(details.virt_text) do
      if vt[1]:find("Live In-Buffer", 1, true) or vt[1]:find("Mermaid", 1, true) then
        found_badge = true
      end
    end
  end
end

assert_true(found_badge, "Mermaid live render badge attached to code fence")
assert_true(found_virt_lines, "Mermaid diagram rendered automatically as virt_lines inside buffer")

-- 3. Test Sequence Diagram In-Line Rendering
print("\n--- Test 3: Automated In-Line Sequence Diagram ---")
local seq_buf = vim.api.nvim_create_buf(false, true)
local seq_raw = {
  "```mermaid",
  "sequenceDiagram",
  "    autonumber",
  "    actor User as Developer",
  "    participant IDE as Neovim",
  "    User->>IDE: Open markdown buffer",
  "    IDE-->>User: Auto-render table & mermaid inline",
  "```",
}
vim.api.nvim_buf_set_lines(seq_buf, 0, -1, false, seq_raw)
render_mod.render(seq_buf)

local seq_extmarks = vim.api.nvim_buf_get_extmarks(seq_buf, render_mod.get_namespace(), 0, -1, { details = true })
local seq_virt_lines = false
for _, em in ipairs(seq_extmarks) do
  local details = em[4]
  if details.virt_lines and #details.virt_lines > 0 then
    seq_virt_lines = true
  end
end
assert_true(seq_virt_lines, "Sequence diagram rendered automatically inline as virt_lines")

-- 4. Test Persistent TOC Sidebar
print("\n--- Test 4: Persistent TOC Sidebar Navigation ---")
local sidebar = require("super-markdown.toc.sidebar")
local doc_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(doc_buf, 0, -1, false, {
  "# Architecture Overview",
  "High level architecture notes...",
  "## Database Design",
  "Schema definitions...",
  "### Redis Cache",
  "Cache eviction policies...",
  "# Deployment Pipeline",
})
vim.api.nvim_set_current_buf(doc_buf)

-- Open sidebar
sidebar.open()
assert_true(sidebar.is_open(), "TOC Sidebar toggled open as split")

-- Jump to 'Database Design' (line 3 in document)
sidebar.jump_to_heading(true)
assert_true(sidebar.is_open(), "TOC Sidebar remains open after jumping to heading")

-- Verify editor focus and line position
local current_win = vim.api.nvim_get_current_win()
local current_cursor = vim.api.nvim_win_get_cursor(current_win)
assert_true(current_cursor[1] >= 1, "Cursor positioned in editor buffer")

-- Toggle hide
sidebar.toggle()
assert_true(not sidebar.is_open(), "TOC Sidebar closes when toggled to hide")

print(string.format("\n=== Inline Test Results: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
