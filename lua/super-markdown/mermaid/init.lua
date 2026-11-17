local preview = require("super-markdown.mermaid.preview")
local ascii = require("super-markdown.mermaid.ascii")
local syntax = require("super-markdown.mermaid.syntax")
local termaid = require("super-markdown.mermaid.termaid")
local config = require("super-markdown.config")

local M = {}
M.syntax = syntax
M.termaid = termaid

local NS_ID = vim.api.nvim_create_namespace("super_markdown_mermaid")
local diagram_cache = {} -- key (renderer:hash) -> virt_lines

function M.clear_cache()
  diagram_cache = {}
end

function M.get_active_renderer()
  local r = (config.options.mermaid and config.options.mermaid.renderer) or "auto"
  if r == "termaid" then
    return "termaid"
  elseif r == "internal" then
    return "internal"
  else
    -- "auto": prefer termaid if installed, fallback to internal pure-Lua
    return termaid.is_available() and "termaid" or "internal"
  end
end

function M.set_renderer(name)
  if name ~= "auto" and name ~= "termaid" and name ~= "internal" then
    vim.notify("SuperMarkdown: Invalid mermaid renderer '" .. tostring(name) .. "'. Choose 'auto', 'termaid', or 'internal'.", vim.log.levels.WARN)
    return
  end
  config.options.mermaid.renderer = name
  M.clear_cache()
  local active = M.get_active_renderer()
  vim.notify(string.format("SuperMarkdown: Mermaid renderer set to '%s' (active: %s) 󰡷", name, active), vim.log.levels.INFO)
  M.render_status()
end

function M.get_namespace()
  return NS_ID
end

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
  -- Always clear standalone mermaid namespace so diagrams never duplicate across BufEnter/TextChanged
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, NS_ID, 0, -1)
  -- Also remove any previously placed mermaid badge/diagram extmarks in ns_id if ns_id differs from NS_ID
  if ns_id ~= NS_ID then
    for idx_clear = 1, 64 do
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, 900000 + idx_clear * 2)
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, 900000 + idx_clear * 2 + 1)
    end
  end
  if opts.enabled == false or opts.inline == false then return end

  local blocks = M.get_blocks(bufnr)

  for b_idx, block in ipairs(blocks) do
    local code = block.code
    local hash = vim.fn.sha256(code)
    local active_renderer = M.get_active_renderer()
    local cache_key = active_renderer .. ":" .. hash

    local virt_lines = diagram_cache[cache_key]
    if not virt_lines then
      local rendered_ok = false
      if active_renderer == "termaid" then
        local t_opts = vim.tbl_deep_extend("force", config.options.mermaid.termaid or {}, opts.termaid or {})
        local ok, t_res = termaid.render(code, t_opts)
        if ok and t_res and t_res.virt_lines and #t_res.virt_lines > 0 then
          virt_lines = t_res.virt_lines
          rendered_ok = true
        end
      end

      if not rendered_ok then
        local ascii_lines = ascii.render(code)
        virt_lines = {}
        for idx, l in ipairs(ascii_lines) do
          if idx == 1 then
            table.insert(virt_lines, { { l, "SuperMarkdownMermaidReady" } })
          elseif ascii.tokenize_line then
            table.insert(virt_lines, ascii.tokenize_line(l))
          else
            table.insert(virt_lines, { { l, "SuperMarkdownTableBorder" } })
          end
        end
      end
      diagram_cache[cache_key] = virt_lines
    end

    -- 1. Attach live rendered diagram as virt_lines right beneath the block
    -- (When the side Live Preview Pane is open, it renders the diagram on the right,
    --  so we omit duplicate virt_lines in the editable buffer for smooth scrolling)
    -- Use priority 85 (below codeblock bottom border priority 90) so the codeblock's
    -- ╰────╯ border closes the code fence before the diagram box begins, and use a
    -- deterministic extmark id per block so it can never stack duplicates.
    local preview_pane_open = package.loaded["super-markdown.preview_pane"]
      and package.loaded["super-markdown.preview_pane"].is_open()
    if not preview_pane_open then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, block.end_lnum - 1, 0, {
        id = 900000 + b_idx * 2,
        virt_lines = virt_lines,
        virt_lines_above = false,
        priority = 85,
      })
    end

    -- 2. Add single unified header banner on the opening ```mermaid fence
    -- (deterministic extmark id prevents stacking)
    local open_line = vim.api.nvim_buf_get_lines(bufnr, block.start_lnum - 1, block.start_lnum, false)[1] or ""
    local indent = open_line:match("^(%s*)") or ""
    local filler = string.rep("─", math.max(4, 60 - 38 - #indent))
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, block.start_lnum - 1, 0, {
      id = 900000 + b_idx * 2 + 1,
      end_col = #open_line,
      conceal = "",
      virt_text = {
        { indent .. "╭─ ", "SuperMarkdownCodeBorder" },
        { "󰡷 mermaid [Live In-Buffer Render]", "SuperMarkdownMermaidReady" },
        { " " .. filler .. "╮", "SuperMarkdownCodeBorder" },
      },
      virt_text_pos = "inline",
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
    else
      -- 4. Syntax highlight the raw mermaid code block lines
      if opts.syntax ~= false and block.end_lnum - block.start_lnum > 1 then
        syntax.highlight_block(bufnr, ns_id, block.start_lnum, block.end_lnum - 2)
      end
    end
  end
end

function M.render_status(bufnr)
  local ok_r, r_mod = pcall(require, "super-markdown.render")
  if ok_r and r_mod.is_enabled(bufnr) then
    r_mod.render(bufnr)
  else
    M.render_inline(bufnr, NS_ID)
  end
end

return M
