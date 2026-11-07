local config = require("super-markdown.config")
local tables = require("super-markdown.render.tables")

local M = {}

local NS_ID = vim.api.nvim_create_namespace("super_markdown_focus")
local buf_states = {} -- bufnr -> { enabled = bool, scope = string, last_range = { from, to } }
local provider_setup = false

function M.get_namespace()
  return NS_ID
end

function M.is_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = buf_states[bufnr]
  if st ~= nil and st.enabled ~= nil then
    return st.enabled
  end
  local f_opts = (config.options and config.options.focus) or {}
  return f_opts.enabled == true
end

function M.get_scope(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = buf_states[bufnr]
  if st ~= nil and st.scope ~= nil then
    return st.scope
  end
  local f_opts = (config.options and config.options.focus) or {}
  return f_opts.scope or "toc"
end

--- Pure Lua fallback for detecting Markdown block boundaries when Treesitter is unavailable
local function get_block_fallback(bufnr, lnum)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return 1, 1, "empty"
  end
  lnum = math.max(1, math.min(line_count, lnum))

  local cur_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  -- 1. If cursor is on empty line, look at adjacent lines
  if vim.trim(cur_line) == "" then
    if lnum > 1 then
      local prev = vim.api.nvim_buf_get_lines(bufnr, lnum - 2, lnum - 1, false)[1] or ""
      if vim.trim(prev) ~= "" then
        return get_block_fallback(bufnr, lnum - 1)
      end
    end
    if lnum < line_count then
      local nxt = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
      if vim.trim(nxt) ~= "" then
        return get_block_fallback(bufnr, lnum + 1)
      end
    end
    return lnum, lnum, "empty"
  end

  -- 2. Code Fence Check (``` or ~~~)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local in_fence = false
  local fence_char = nil
  local fence_start = nil
  for idx, l in ipairs(all_lines) do
    if not in_fence then
      local ind, char = l:match("^(%s*)(```+)")
      if not ind then
        ind, char = l:match("^(%s*)(~~~+)")
      end
      if ind then
        in_fence = true
        fence_char = char:sub(1, 1)
        fence_start = idx
      end
    else
      local close_pat = (fence_char == "~") and "^%s*~~~+%s*$" or "^%s*```+%s*$"
      if l:match(close_pat) then
        if lnum >= fence_start and lnum <= idx then
          return fence_start, idx, "fenced_code_block"
        end
        in_fence = false
        fence_start = nil
      end
    end
  end
  if in_fence and fence_start and lnum >= fence_start then
    return fence_start, line_count, "fenced_code_block"
  end

  -- 3. Table Check
  if tables.is_table_row(cur_line) then
    local s_l = lnum
    while s_l > 1 and tables.is_table_row(all_lines[s_l - 1]) do
      s_l = s_l - 1
    end
    local e_l = lnum
    while e_l < line_count and tables.is_table_row(all_lines[e_l + 1]) do
      e_l = e_l + 1
    end
    return s_l, e_l, "pipe_table"
  end

  -- 4. Callout / Blockquote Check
  if cur_line:match("^%s*>") then
    local s_l = lnum
    while s_l > 1 and all_lines[s_l - 1]:match("^%s*>") do
      s_l = s_l - 1
    end
    local e_l = lnum
    while e_l < line_count and all_lines[e_l + 1]:match("^%s*>") do
      e_l = e_l + 1
    end
    return s_l, e_l, "block_quote"
  end

  -- 5. Heading Check
  if cur_line:match("^%s*#+%s") then
    return lnum, lnum, "atx_heading"
  end

  -- 6. Horizontal Divider Check
  if cur_line:match("^%s*%-%s*%-%s*%-") or cur_line:match("^%s*%*%s*%*%s*%*") or cur_line:match("^%s*_%s*_%s*_") then
    return lnum, lnum, "thematic_break"
  end

  -- 7. List Item / List Block Check
  if cur_line:match("^%s*[%-%*%+]%s") or cur_line:match("^%s*%d+%.%s") then
    local s_l = lnum
    while s_l > 1 do
      local prev = all_lines[s_l - 1]
      if prev:match("^%s*[%-%*%+]%s") or prev:match("^%s*%d+%.%s") or (prev:match("^%s+%S") and not prev:match("^%s*#")) then
        s_l = s_l - 1
      else
        break
      end
    end
    local e_l = lnum
    while e_l < line_count do
      local nxt = all_lines[e_l + 1]
      if nxt:match("^%s*[%-%*%+]%s") or nxt:match("^%s*%d+%.%s") or (nxt:match("^%s+%S") and not nxt:match("^%s*#")) then
        e_l = e_l + 1
      else
        break
      end
    end
    return s_l, e_l, "list"
  end

  -- 8. Paragraph Check
  local s_l = lnum
  while s_l > 1 do
    local prev = all_lines[s_l - 1]
    if vim.trim(prev) == "" or prev:match("^%s*#") or prev:match("^%s*```") or prev:match("^%s*~~~")
      or tables.is_table_row(prev) or prev:match("^%s*>") or prev:match("^%s*[%-%*%+]%s") or prev:match("^%s*%d+%.%s") then
      break
    end
    s_l = s_l - 1
  end

  local e_l = lnum
  while e_l < line_count do
    local nxt = all_lines[e_l + 1]
    if vim.trim(nxt) == "" or nxt:match("^%s*#") or nxt:match("^%s*```") or nxt:match("^%s*~~~")
      or tables.is_table_row(nxt) or nxt:match("^%s*>") or nxt:match("^%s*[%-%*%+]%s") or nxt:match("^%s*%d+%.%s") then
      break
    end
    e_l = e_l + 1
  end

  return s_l, e_l, "paragraph"
end

--- Computes the start and end line (1-indexed inclusive) of the block or section containing `lnum`
--- @param bufnr number
--- @param lnum number
--- @param scope? "block"|"section"
--- @return number start_line, number end_line, string kind
function M.get_block_range(bufnr, lnum, scope)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 1, 1, "invalid"
  end

  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  if total_lines == 0 then
    return 1, 1, "empty"
  end
  lnum = math.max(1, math.min(total_lines, lnum or 1))
  scope = scope or M.get_scope(bufnr)

  -- 1. TOC scope (default): focuses the active TOC section (from current heading to next heading in the TOC)
  if scope == "toc" then
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local in_fence = false
    local headings = {}

    for idx, l in ipairs(all_lines) do
      if l:match("^%s*```") or l:match("^%s*~~~") then
        in_fence = not in_fence
      elseif not in_fence then
        local hashes = l:match("^%s*(#+)%s")
        if hashes and #hashes <= 6 then
          table.insert(headings, { lnum = idx, level = #hashes })
        end
      end
    end

    if #headings == 0 then
      return 1, total_lines, "toc_document"
    end

    -- Preamble before first TOC heading
    if lnum < headings[1].lnum then
      return 1, math.max(1, headings[1].lnum - 1), "toc_preamble"
    end

    -- Find the TOC heading containing lnum
    for i = 1, #headings do
      local cur_h = headings[i]
      local next_h = headings[i + 1]
      if not next_h or lnum < next_h.lnum then
        local start_line = cur_h.lnum
        local end_line = next_h and (next_h.lnum - 1) or total_lines
        return start_line, end_line, "toc_heading"
      end
    end

    return 1, total_lines, "toc"
  end

  -- 2. Root scope: focuses the active root section in the TOC (from root heading to next root heading)
  if scope == "root" then
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local in_fence = false
    local headings = {}
    local min_lvl = 6

    for idx, l in ipairs(all_lines) do
      if l:match("^%s*```") or l:match("^%s*~~~") then
        in_fence = not in_fence
      elseif not in_fence then
        local hashes = l:match("^%s*(#+)%s")
        if hashes and #hashes <= 6 then
          local lvl = #hashes
          table.insert(headings, { lnum = idx, level = lvl })
          if lvl < min_lvl then
            min_lvl = lvl
          end
        end
      end
    end

    if #headings == 0 then
      return 1, total_lines, "root_document"
    end

    local roots = {}
    for _, h in ipairs(headings) do
      if h.level == min_lvl then
        table.insert(roots, h)
      end
    end

    if lnum < roots[1].lnum then
      return 1, math.max(1, roots[1].lnum - 1), "root_preamble"
    end

    -- If there is only one root and it has subheadings, check if cursor is in root intro
    if #roots == 1 and #headings > 1 then
      local first_sub = headings[2]
      if lnum < first_sub.lnum then
        return roots[1].lnum, math.max(roots[1].lnum, first_sub.lnum - 1), "root_intro"
      end
    end

    for i = 1, #roots do
      local cur_r = roots[i]
      local next_r = roots[i + 1]
      if not next_r or lnum < next_r.lnum then
        local start_line = cur_r.lnum
        local end_line = next_r and (next_r.lnum - 1) or total_lines
        return start_line, end_line, "root_section"
      end
    end

    return 1, total_lines, "root"
  end

  -- 3. Section scope: from current heading to next heading of same or higher level
  if scope == "section" then
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cur_head_idx = nil
    local cur_head_lvl = 1

    for l = lnum, 1, -1 do
      local hashes = all_lines[l]:match("^%s*(#+)%s")
      if hashes then
        cur_head_idx = l
        cur_head_lvl = #hashes
        break
      end
    end

    if not cur_head_idx then
      -- Document preamble before first heading
      local end_preamble = total_lines
      for l = 1, total_lines do
        if all_lines[l]:match("^%s*#+%s") then
          end_preamble = math.max(1, l - 1)
          break
        end
      end
      return 1, end_preamble, "section_preamble"
    end

    -- If root heading (level 1) has subheadings, check if cursor is before first child subheading
    local first_child_idx = nil
    for l = cur_head_idx + 1, total_lines do
      local hashes = all_lines[l]:match("^%s*(#+)%s")
      if hashes then
        if #hashes > cur_head_lvl and not first_child_idx then
          first_child_idx = l
        end
        if #hashes <= cur_head_lvl then
          break
        end
      end
    end

    if first_child_idx and lnum < first_child_idx then
      return cur_head_idx, math.max(cur_head_idx, first_child_idx - 1), "section_root_intro"
    end

    local end_sec = total_lines
    for l = cur_head_idx + 1, total_lines do
      local hashes = all_lines[l]:match("^%s*(#+)%s")
      if hashes and #hashes <= cur_head_lvl then
        end_sec = math.max(cur_head_idx, l - 1)
        break
      end
    end
    return cur_head_idx, end_sec, "section"
  end

  -- 2. Block scope (default): paragraph, codeblock, table, callout, list, heading, divider
  local cur_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  local target_lnum = lnum

  -- If line is blank, probe adjacent non-blank lines so the focus doesn't flash
  if vim.trim(cur_line) == "" then
    if lnum > 1 then
      local prev = vim.api.nvim_buf_get_lines(bufnr, lnum - 2, lnum - 1, false)[1] or ""
      if vim.trim(prev) ~= "" then
        target_lnum = lnum - 1
      end
    elseif lnum < total_lines then
      local nxt = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
      if vim.trim(nxt) ~= "" then
        target_lnum = lnum + 1
      end
    end
  end

  -- Try Treesitter AST
  local ok_ts, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if ok_ts and parser then
    local ok_tree, tree = pcall(function() return parser:parse()[1] end)
    if ok_tree and tree then
      local root = tree:root()
      local row = target_lnum - 1
      local node = root:named_descendant_for_range(row, 0, row, 0)
      local BLOCK_TYPES = {
        paragraph = true,
        fenced_code_block = true,
        pipe_table = true,
        block_quote = true,
        list = true,
        atx_heading = true,
        thematic_break = true,
      }
      local n = node
      while n and not BLOCK_TYPES[n:type()] do
        if n:type() == "document" or n:type() == "section" then
          break
        end
        n = n:parent()
      end
      if n and BLOCK_TYPES[n:type()] then
        local sr, sc, er, ec = n:range()
        local start_line = sr + 1
        local end_line = (ec > 0) and (er + 1) or er
        if end_line < start_line then end_line = start_line end
        return start_line, math.min(total_lines, end_line), n:type()
      end
    end
  end

  -- Fallback to pure Lua block detector
  return get_block_fallback(bufnr, target_lnum)
end

function M.setup_provider()
  if provider_setup then return end
  provider_setup = true

  vim.api.nvim_set_decoration_provider(NS_ID, {
    on_win = function(_, win, bufnr, top, bottom)
      if not (M.is_enabled(bufnr) and vim.api.nvim_win_is_valid(win)) then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(win)
      local cur_line = cursor[1]
      local from, to = M.get_block_range(bufnr, cur_line)

      if not buf_states[bufnr] then
        buf_states[bufnr] = { enabled = true }
      end
      buf_states[bufnr].last_range = { from, to }

      local dim_hl = (config.options and config.options.focus and config.options.focus.dim_hl) or "SuperMarkdownDimmed"
      local prio = (config.options and config.options.focus and config.options.focus.priority) or 250

      -- 1. Dim visible lines above the active block [top .. from - 1]
      local top_dim_end = math.min(from - 1, bottom + 1)
      if top < top_dim_end then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_ID, top, 0, {
          end_row = top_dim_end,
          end_col = 0,
          hl_group = dim_hl,
          hl_eol = true,
          priority = prio,
          ephemeral = true,
        })
      end

      -- 2. Dim visible lines below the active block [to .. bottom + 1]
      local bot_dim_start = math.max(to, top)
      if bot_dim_start < bottom + 1 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_ID, bot_dim_start, 0, {
          end_row = bottom + 1,
          end_col = 0,
          hl_group = dim_hl,
          hl_eol = true,
          priority = prio,
          ephemeral = true,
        })
      end
    end,
  })
end

function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  M.setup_provider()

  local group = vim.api.nvim_create_augroup("SuperMarkdownFocus_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if M.is_enabled(bufnr) then
        local cursor = vim.api.nvim_win_get_cursor(0)
        local st = buf_states[bufnr]
        if st and st.last_range then
          if cursor[1] < st.last_range[1] or cursor[1] > st.last_range[2] then
            pcall(vim.cmd, "redraw")
          end
        else
          pcall(vim.cmd, "redraw")
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      buf_states[bufnr] = nil
    end,
  })
end

function M.set_enabled(bufnr, state, scope)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not buf_states[bufnr] then
    buf_states[bufnr] = {}
  end
  buf_states[bufnr].enabled = state
  if scope then
    buf_states[bufnr].scope = scope
  end

  M.setup_provider()
  M.attach(bufnr)

  pcall(vim.cmd, "redraw!")
end

function M.toggle(bufnr, state, scope)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cur = M.is_enabled(bufnr)
  local new_state = (state ~= nil) and state or (not cur)

  if type(state) == "string" then
    if state == "on" or state == "enable" then
      new_state = true
    elseif state == "off" or state == "disable" then
      new_state = false
    elseif state == "toc" or state == "root" or state == "section" or state == "block" then
      new_state = true
      scope = state
    elseif state == "toggle" then
      new_state = not cur
    end
  end

  M.set_enabled(bufnr, new_state, scope)

  local cur_scope = M.get_scope(bufnr)
  vim.notify(
    string.format("SuperMarkdown Focus: %s (%s)", new_state and "Enabled 󰄵" or "Disabled 󰄱", cur_scope),
    vim.log.levels.INFO
  )
  return new_state
end

function M.enable(bufnr, scope)
  return M.set_enabled(bufnr, true, scope)
end

function M.disable(bufnr)
  return M.set_enabled(bufnr, false)
end

return M