local config = require("super-markdown.config")

local M = {}

local cb_cache = {} -- bufnr -> { tick = changedtick, intervals = { {start, finish}, ... } }

--- Get cached codeblock intervals for a buffer, refreshed only when changedtick changes
--- @param bufnr number
--- @return table
local function get_codeblock_intervals(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local c = cb_cache[bufnr]
  if c and c.tick == tick then
    return c.intervals
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local intervals = {}
  local block_start = nil

  for i, line in ipairs(lines) do
    if line:match("^%s*```") or line:match("^%s*~~~") then
      if not block_start then
        block_start = i
      else
        table.insert(intervals, { block_start, i })
        block_start = nil
      end
    end
  end
  if block_start then
    table.insert(intervals, { block_start, #lines })
  end

  cb_cache[bufnr] = { tick = tick, intervals = intervals }
  return intervals
end

--- Check if a 1-indexed line number is inside a fenced code block (``` or ~~~)
--- @param lnum number
--- @param bufnr number|nil
--- @return boolean
local function is_in_codeblock(lnum, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local intervals = get_codeblock_intervals(bufnr)
  for _, iv in ipairs(intervals) do
    if lnum >= iv[1] and lnum <= iv[2] then
      return true
    end
  end
  return false
end

--- Calculate fold level for a markdown line.
--- In "toc" mode (default), every heading (# through ######) starts a level-1 fold (>1)
--- so that folding all sections (zM) keeps every heading visible as an interactive Table of Contents,
--- folding only the body text beneath each heading.
--- In "tree" mode, headings define nested folds (>1, >2, >3...).
--- @param lnum number 1-indexed line number
--- @return string fold expression result
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  local hashes = line:match("^%s*(#+)%s")
  if hashes then
    local level = #hashes
    if level >= 1 and level <= 6 and not is_in_codeblock(lnum) then
      local mode = (config.options and config.options.folds and config.options.folds.mode) or "toc"
      if mode == "tree" then
        return ">" .. level
      end
      return ">1"
    end
  end
  return "="
end

local foldtext_cache = {} -- bufnr -> { tick = number, items = { [key] = string } }

--- Custom foldtext display showing indentation, closed folder icon, heading icon, title, spec task rollup, and line count
--- @return string
function M.foldtext()
  local start_lnum = vim.v.foldstart
  local end_lnum = vim.v.foldend
  local bufnr = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local fc = foldtext_cache[bufnr]
  if not fc or fc.tick ~= tick then
    fc = { tick = tick, items = {} }
    foldtext_cache[bufnr] = fc
  end
  local cache_key = start_lnum .. ":" .. end_lnum
  if fc.items[cache_key] then
    return fc.items[cache_key]
  end

  local count = end_lnum - start_lnum + 1
  local start_line = vim.fn.getline(start_lnum)

  -- Scan folded lines for task completion, blockers, and questions
  local checked, total_tasks, blockers, questions = 0, 0, 0, 0
  local folded_lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  for _, line in ipairs(folded_lines) do
    if line:find("[", 1, true) then
      local cb = line:match("^%s*[%-%*%+]%s+%[(.)%]") or line:match("^%s*%d+%.%s+%[(.)%]")
      if cb then
        if cb == "x" or cb == "X" then
          checked = checked + 1
          total_tasks = total_tasks + 1
        elseif cb == " " or cb == "/" then
          total_tasks = total_tasks + 1
        elseif cb == "!" then
          blockers = blockers + 1
          total_tasks = total_tasks + 1
        elseif cb == "?" then
          questions = questions + 1
        end
      end
    end
  end

  local spec_parts = {}
  if total_tasks > 0 then
    table.insert(spec_parts, string.format("󰄵 %d/%d", checked, total_tasks))
  end
  if blockers > 0 then
    table.insert(spec_parts, string.format("󰀦 %d", blockers))
  end
  if questions > 0 then
    table.insert(spec_parts, string.format("󰋽 %d", questions))
  end
  local spec_str = #spec_parts > 0 and ("  [" .. table.concat(spec_parts, " · ") .. "]") or ""

  local hashes, title = start_line:match("^%s*(#+)%s*(.*)$")
  local result
  if hashes then
    local level = math.min(#hashes, 6)
    local h_opts = (config.options and config.options.render and config.options.render.headings) or {}
    local icons = h_opts.icons
    local icon = (icons and icons[level]) or (string.rep("#", level) .. " ")
    local folder = (h_opts.closed_folder_icon ~= false) and (h_opts.closed_folder_icon or "󰉋 ") or ""
    local indent = string.rep("  ", level - 1)
    result = string.format(" %s%s%s%s%s  ⋯ (%d lines)", indent, folder, icon, title, spec_str, count)
  else
    result = string.format(" %s%s  ⋯ (%d lines)", vim.trim(start_line), spec_str, count)
  end

  fc.items[cache_key] = result
  return result
end

--- Calculate fold level for preview pane lines
--- @param lnum number 1-indexed preview line
--- @return string fold expression result
function M.preview_foldexpr(lnum)
  local ok_pp, pp = pcall(require, "super-markdown.preview_pane")
  if ok_pp and pp.get_meta then
    local meta = pp.get_meta(lnum)
    if meta and meta.is_heading then
      local mode = (config.options and config.options.folds and config.options.folds.mode) or "toc"
      if mode == "tree" then
        return ">" .. (meta.level or 1)
      end
      return ">1"
    end
  end
  local line = vim.fn.getline(lnum)
  if line:match("^%s*󰲡") or line:match("^%s*󰲣") or line:match("^%s*󰲥")
    or line:match("^%s*󰲧") or line:match("^%s*󰲩") or line:match("^%s*󰲫")
    or line:match("^%s*#+%s") then
    return ">1"
  end
  return "="
end

--- Custom foldtext display for preview pane
--- @return string
function M.preview_foldtext()
  local start_lnum = vim.v.foldstart
  local end_lnum = vim.v.foldend
  local count = end_lnum - start_lnum + 1
  local start_line = vim.fn.getline(start_lnum)
  return string.format(" %s  ⋯ (%d lines)", vim.trim(start_line), count)
end

--- Apply fold settings to a preview pane window
--- @param win number Window ID
--- @param bufnr number Buffer number
function M.attach_preview_win(win, bufnr)
  if not win or win == -1 or not vim.api.nvim_win_is_valid(win) then return end
  local opts = (config.options and config.options.folds) or {}
  if opts.enabled == false then return end

  pcall(vim.api.nvim_set_option_value, "foldenable", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "foldmethod", "expr", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldexpr", "v:lua.require'super-markdown.folds'.preview_foldexpr(v:lnum)", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", tostring(opts.foldcolumn or "1"), { win = win })
  pcall(vim.api.nvim_set_option_value, "foldlevel", opts.foldlevel or 99, { win = win })

  if opts.foldtext ~= false then
    pcall(vim.api.nvim_set_option_value, "foldtext", "v:lua.require'super-markdown.folds'.preview_foldtext()", { win = win })
  end

  local current = ""
  pcall(function()
    current = vim.wo[win].fillchars or ""
  end)

  local parts = {}
  for _, item in ipairs(vim.split(current, ",")) do
    local k = vim.split(item, ":")[1]
    if k ~= "" and k ~= "foldopen" and k ~= "foldclose" and k ~= "foldsep" then
      table.insert(parts, item)
    end
  end

  table.insert(parts, "foldopen:" .. (opts.foldopen or "-"))
  table.insert(parts, "foldclose:" .. (opts.foldclose or "+"))
  table.insert(parts, "foldsep:" .. (opts.foldsep or "│"))

  pcall(vim.api.nvim_set_option_value, "fillchars", table.concat(parts, ","), { win = win })
end

--- Apply fold settings to a specific window
--- @param win number Window ID
--- @param bufnr number Buffer number
function M.attach_win(win, bufnr)
  if not win or win == -1 or not vim.api.nvim_win_is_valid(win) then return end
  local opts = (config.options and config.options.folds) or {}
  if opts.enabled == false then return end

  pcall(vim.api.nvim_set_option_value, "foldmethod", "expr", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldexpr", "v:lua.require'super-markdown.folds'.foldexpr(v:lnum)", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", tostring(opts.foldcolumn or "1"), { win = win })
  pcall(vim.api.nvim_set_option_value, "foldlevel", opts.foldlevel or 99, { win = win })

  if opts.foldtext ~= false then
    pcall(vim.api.nvim_set_option_value, "foldtext", "v:lua.require'super-markdown.folds'.foldtext()", { win = win })
  end

  -- Merge fillchars for foldopen, foldclose, foldsep (+ and - gutter icons)
  local current = ""
  pcall(function()
    current = vim.wo[win].fillchars or ""
  end)

  local parts = {}
  for _, item in ipairs(vim.split(current, ",")) do
    local k = vim.split(item, ":")[1]
    if k ~= "" and k ~= "foldopen" and k ~= "foldclose" and k ~= "foldsep" then
      table.insert(parts, item)
    end
  end

  table.insert(parts, "foldopen:" .. (opts.foldopen or "-"))
  table.insert(parts, "foldclose:" .. (opts.foldclose or "+"))
  table.insert(parts, "foldsep:" .. (opts.foldsep or "│"))

  pcall(vim.api.nvim_set_option_value, "fillchars", table.concat(parts, ","), { win = win })
end

--- Attach fold management to a buffer and its current/future windows
--- @param bufnr number Buffer number
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    M.attach_win(win, bufnr)
  end

  local group = vim.api.nvim_create_augroup("SuperMarkdownFolds_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = bufnr,
    callback = function(args)
      local win = vim.fn.bufwinid(args.buf)
      if win and win ~= -1 then
        M.attach_win(win, args.buf)
      end
    end,
  })
end

--- Resolve active markdown source window/buffer, preview window/buffer, and sidebar window/buffer
--- @return table { source_win, source_buf, preview_win, preview_buf, sidebar_win, sidebar_buf }
function M.resolve_windows()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()

  local s_buf = nil
  local s_win = nil
  local p_win = nil
  local p_buf = nil
  local sb_win = nil
  local sb_buf = nil

  local ok_pp, pp = pcall(require, "super-markdown.preview_pane")
  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")

  if ok_sb and sb.is_open() then
    sb_win = sb.get_window()
    sb_buf = sb.get_buf()
  end

  if ok_pp and pp.is_open() then
    p_win = pp.get_window()
    p_buf = pp.get_buffer()
    s_win = pp.get_source_win()
    s_buf = pp.get_source_buf()
  end

  if not s_buf then
    local toc = require("super-markdown.toc")
    s_buf = toc.resolve_markdown_buf(cur_buf)
  end

  if not s_win or not vim.api.nvim_win_is_valid(s_win) then
    if cur_buf == s_buf and cur_win ~= p_win and cur_win ~= sb_win then
      s_win = cur_win
    else
      local wins = vim.fn.win_findbuf(s_buf)
      for _, w in ipairs(wins) do
        if w ~= p_win and w ~= sb_win and vim.api.nvim_win_is_valid(w) then
          s_win = w
          break
        end
      end
    end
  end

  return {
    source_win = s_win,
    source_buf = s_buf,
    preview_win = p_win,
    preview_buf = p_buf,
    sidebar_win = sb_win,
    sidebar_buf = sb_buf,
  }
end

--- Find the nearest preceding heading at or before lnum in a markdown buffer
--- @param bufnr number
--- @param lnum number
--- @return table|nil heading
function M.find_heading_at(bufnr, lnum)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  local toc = require("super-markdown.toc")
  local headings = toc.get_headings(bufnr)
  local latest = nil
  for _, h in ipairs(headings) do
    if h.lnum <= lnum then
      latest = h
    else
      break
    end
  end
  return latest
end

--- Find line numbers of all descendant child headings under target_lnum
--- @param bufnr number
--- @param target_lnum number
--- @return table list of source line numbers
function M.find_heading_descendants(bufnr, target_lnum)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return {} end
  local toc = require("super-markdown.toc")
  local headings = toc.get_headings(bufnr)
  local target_idx = nil
  for i, h in ipairs(headings) do
    if h.lnum == target_lnum then
      target_idx = i
      break
    end
  end
  if not target_idx then return {} end

  local target_level = headings[target_idx].level
  local desc = {}
  for j = target_idx + 1, #headings do
    if headings[j].level > target_level then
      table.insert(desc, headings[j].lnum)
    else
      break
    end
  end
  return desc
end

local function resolve_target_lnum(wins, target_lnum)
  if target_lnum then return target_lnum end
  local cur_win = vim.api.nvim_get_current_win()

  if cur_win == wins.sidebar_win then
    local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
    if ok_sb then
      local row = vim.api.nvim_win_get_cursor(cur_win)[1]
      local item = sb.get_item_at_row(row)
      if item and item.heading then
        return item.heading.lnum
      end
    end
  elseif cur_win == wins.preview_win then
    local ok_pp, pp = pcall(require, "super-markdown.preview_pane")
    if ok_pp then
      local p_row = vim.api.nvim_win_get_cursor(cur_win)[1]
      local s_l = pp.map_preview_to_source(p_row)
      local h = M.find_heading_at(wins.source_buf, s_l or 1)
      if h then return h.lnum end
    end
  else
    local s_row = vim.api.nvim_win_get_cursor(wins.source_win or 0)[1]
    local h = M.find_heading_at(wins.source_buf, s_row)
    if h then return h.lnum end
  end

  local h1 = M.find_heading_at(wins.source_buf, 1)
  return h1 and h1.lnum or 1
end

local function ensure_folds_attached(wins)
  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(function()
      if vim.wo[wins.source_win].foldmethod ~= "expr" or not vim.wo[wins.source_win].foldenable then
        M.attach_win(wins.source_win, wins.source_buf)
      end
    end)
  end
  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    pcall(function()
      if vim.wo[wins.preview_win].foldmethod ~= "expr" or not vim.wo[wins.preview_win].foldenable then
        M.attach_preview_win(wins.preview_win, wins.preview_buf)
      end
    end)
  end
end

--- Collapse a heading and its children across sidebar, edit view, and preview pane
--- @param target_lnum number|nil Source line number (optional; defaults to heading at active cursor)
function M.collapse_header(target_lnum)
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)
  target_lnum = resolve_target_lnum(wins, target_lnum)
  if not target_lnum then return end

  local desc = M.find_heading_descendants(wins.source_buf, target_lnum)

  -- 1. Fold in source (editor) window
  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      for _, d_lnum in ipairs(desc) do
        pcall(vim.api.nvim_win_set_cursor, wins.source_win, { d_lnum, 0 })
        pcall(vim.cmd, "normal! zc")
      end
      pcall(vim.api.nvim_win_set_cursor, wins.source_win, { target_lnum, 0 })
      pcall(vim.cmd, "normal! zc")
    end)
  end

  -- 2. Fold in preview window
  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    local pp = require("super-markdown.preview_pane")
    pcall(vim.api.nvim_win_call, wins.preview_win, function()
      for _, d_lnum in ipairs(desc) do
        local p_d = pp.map_source_to_preview(d_lnum)
        if p_d and p_d > 0 then
          pcall(vim.api.nvim_win_set_cursor, wins.preview_win, { p_d, 0 })
          pcall(vim.cmd, "normal! zc")
        end
      end
      local p_lnum = pp.map_source_to_preview(target_lnum)
      if p_lnum and p_lnum > 0 then
        pcall(vim.api.nvim_win_set_cursor, wins.preview_win, { p_lnum, 0 })
        pcall(vim.cmd, "normal! zc")
      end
    end)
  end

  -- 3. Update sidebar collapsed state
  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb then
    sb.set_collapsed(target_lnum, true)
    if sb.is_open() then
      sb.refresh()
    end
  end
end

--- Expand a heading across sidebar, edit view, and preview pane
--- @param target_lnum number|nil Source line number (optional)
function M.expand_header(target_lnum)
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)
  target_lnum = resolve_target_lnum(wins, target_lnum)
  if not target_lnum then return end

  -- 1. Unfold in source (editor) window
  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      pcall(vim.api.nvim_win_set_cursor, wins.source_win, { target_lnum, 0 })
      pcall(vim.cmd, "normal! zo")
    end)
  end

  -- 2. Unfold in preview window
  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    local pp = require("super-markdown.preview_pane")
    local p_lnum = pp.map_source_to_preview(target_lnum)
    if p_lnum and p_lnum > 0 then
      pcall(vim.api.nvim_win_call, wins.preview_win, function()
        pcall(vim.api.nvim_win_set_cursor, wins.preview_win, { p_lnum, 0 })
        pcall(vim.cmd, "normal! zo")
      end)
    end
  end

  -- 3. Update sidebar collapsed state
  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb then
    sb.set_collapsed(target_lnum, false)
    if sb.is_open() then
      sb.refresh()
    end
  end
end

--- Toggle header fold across sidebar, edit view, and preview pane
--- @param target_lnum number|nil Source line number (optional)
function M.toggle_header(target_lnum)
  local wins = M.resolve_windows()
  target_lnum = resolve_target_lnum(wins, target_lnum)
  if not target_lnum then return end

  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  local is_col = false
  if ok_sb and sb.is_collapsed(target_lnum) then
    is_col = true
  elseif wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    local folded = vim.api.nvim_win_call(wins.source_win, function()
      return vim.fn.foldclosed(target_lnum)
    end)
    if folded ~= -1 then
      is_col = true
    end
  end

  if is_col then
    M.expand_header(target_lnum)
  else
    M.collapse_header(target_lnum)
  end
end

--- Collapse all sections across sidebar, edit view, and preview pane (zM)
function M.collapse_all()
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)

  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      vim.cmd("normal! zM")
    end)
  end

  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    pcall(vim.api.nvim_win_call, wins.preview_win, function()
      vim.cmd("normal! zM")
    end)
  end

  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb and sb.collapse_all_internal then
    sb.collapse_all_internal()
  end

  vim.notify("SuperMarkdown: Collapsed all sections across sidebar, editor & preview 󰉋", vim.log.levels.INFO)
end

--- Expand all sections across sidebar, edit view, and preview pane (zR)
function M.expand_all()
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)

  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      vim.cmd("normal! zR")
    end)
  end

  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    pcall(vim.api.nvim_win_call, wins.preview_win, function()
      vim.cmd("normal! zR")
    end)
  end

  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb and sb.expand_all_internal then
    sb.expand_all_internal()
  end

  vim.notify("SuperMarkdown: Expanded all sections across sidebar, editor & preview 󰝰", vim.log.levels.INFO)
end

--- Fold more (decrease fold level across views - zm)
function M.fold_more()
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)
  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      vim.cmd("normal! zm")
    end)
  end
  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    pcall(vim.api.nvim_win_call, wins.preview_win, function()
      vim.cmd("normal! zm")
    end)
  end
  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb and sb.fold_more_internal then
    sb.fold_more_internal()
  end
end

--- Fold less (increase fold level across views - zr)
function M.fold_less()
  local wins = M.resolve_windows()
  ensure_folds_attached(wins)
  if wins.source_win and vim.api.nvim_win_is_valid(wins.source_win) then
    pcall(vim.api.nvim_win_call, wins.source_win, function()
      vim.cmd("normal! zr")
    end)
  end
  if wins.preview_win and vim.api.nvim_win_is_valid(wins.preview_win) then
    pcall(vim.api.nvim_win_call, wins.preview_win, function()
      vim.cmd("normal! zr")
    end)
  end
  local ok_sb, sb = pcall(require, "super-markdown.toc.sidebar")
  if ok_sb and sb.fold_less_internal then
    sb.fold_less_internal()
  end
end

--- Handle <CR> in Normal mode: if on a folded line or a Markdown heading, toggle fold!
--- @return boolean handled
function M.handle_normal_enter()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if vim.fn.foldclosed(lnum) ~= -1 then
    M.expand_header(lnum)
    return true
  end
  local line = vim.fn.getline(lnum)
  if line:match("^%s*#+%s") and not is_in_codeblock(lnum) then
    M.toggle_header(lnum)
    return true
  end
  return false
end

--- Set fold level in current window
--- @param level number Target fold level (e.g. 1 for H1 only, 2 for H1+H2)
function M.fold_level(level)
  level = tonumber(level) or 0
  pcall(vim.api.nvim_set_option_value, "foldlevel", level, { win = 0 })
  vim.notify(string.format("SuperMarkdown: Fold level set to %d", level), vim.log.levels.INFO)
end

--- Backward compatibility aliases
M.fold_all = M.collapse_all
M.unfold_all = M.expand_all
M.fold_toc = M.collapse_all
M.toggle_fold = M.toggle_header

return M
