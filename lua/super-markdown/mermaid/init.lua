local preview = require("super-markdown.mermaid.preview")
local ascii = require("super-markdown.mermaid.ascii")
local config = require("super-markdown.config")

local M = {}

local NS_ID = vim.api.nvim_create_namespace("super_markdown_mermaid")
local diagram_cache = {} -- hash -> virt_lines

function M.get_blocks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local in_block = false
  local start_lnum = 0
  local code_lines = {}

  for lnum, line in ipairs(lines) do
    if not in_block and line:match("^%s*```mermaid") then
      in_block = true
      start_lnum = lnum
      code_lines = {}
    elseif in_block and line:match("^%s*```%s*$") then
      in_block = false
      table.insert(blocks, {
        start_lnum = start_lnum,
        end_lnum = lnum,
        code = table.concat(code_lines, "\n"),
      })
    elseif in_block then
      table.insert(code_lines, line)
    end
  end

  return blocks
end

function M.get_block_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local blocks = M.get_blocks(bufnr)

  for _, block in ipairs(blocks) do
    if cursor_line >= block.start_lnum and cursor_line <= block.end_lnum then
      return block
    end
  end

  if #blocks > 0 then
    local closest = blocks[1]
    local min_dist = math.abs(cursor_line - closest.start_lnum)
    for i = 2, #blocks do
      local dist = math.abs(cursor_line - blocks[i].start_lnum)
      if dist < min_dist then
        min_dist = dist
        closest = blocks[i]
      end
    end
    return closest
  end

  return nil
end

function M.preview_under_cursor()
  local block = M.get_block_at_cursor()
  if not block then
    vim.notify("SuperMarkdown: No Mermaid diagram block found in buffer", vim.log.levels.WARN)
    return
  end

  preview.open(block.code)
end

--- Render all Mermaid diagrams automatically in line into the buffer
function M.render_inline(bufnr, ns_id, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  ns_id = ns_id or NS_ID
  opts = opts or config.options.mermaid or {}

  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if opts.enabled == false or opts.inline == false then return end

  local blocks = M.get_blocks(bufnr)

  for _, block in ipairs(blocks) do
    local code = block.code
    local hash = vim.fn.sha256(code)

    local virt_lines = diagram_cache[hash]
    if not virt_lines then
      local ascii_lines = ascii.render(code)
      virt_lines = {}
      for _, l in ipairs(ascii_lines) do
        table.insert(virt_lines, { { l, "SuperMarkdownTableBorder" } })
      end
      diagram_cache[hash] = virt_lines
    end

    -- 1. Attach live rendered diagram as virt_lines right beneath the block
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, block.end_lnum - 1, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
      priority = 92,
    })

    -- 2. Add badge on the opening ```mermaid fence
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, block.start_lnum - 1, 0, {
      virt_text = {
        { " 󰡷 [Live In-Buffer Render] ", "SuperMarkdownMermaidReady" },
      },
      virt_text_pos = "eol",
      priority = 95,
    })

    -- 3. Optionally conceal raw code if conceal_code is enabled
    if opts.conceal_code and block.end_lnum - block.start_lnum > 1 then
      for c_line = block.start_lnum, block.end_lnum - 2 do
        local l_text = vim.api.nvim_buf_get_lines(bufnr, c_line, c_line + 1, false)[1] or ""
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, c_line, 0, {
          end_col = #l_text,
          conceal = "",
          priority = 90,
        })
      end
    end
  end
end

function M.render_status(bufnr)
  M.render_inline(bufnr)
end

return M
