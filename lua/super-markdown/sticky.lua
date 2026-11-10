local config = require("super-markdown.config")
local toc = require("super-markdown.toc")

local M = {}

local active_floats = {} -- target_win -> { float_win, float_buf, stacked }
local augroup_id = nil
local NS_ID = vim.api.nvim_create_namespace("super_markdown_sticky_headers")

--- Check if sticky stacked headers are enabled
--- @return boolean
function M.is_enabled()
  local s_opts = (config.options and config.options.sticky) or {}
  return s_opts.enabled == true
end

--- Enable sticky stacked headers
function M.enable()
  config.options.sticky = config.options.sticky or {}
  config.options.sticky.enabled = true
  M.setup_autocmds()
  M.update_all()
  vim.notify("SuperMarkdown: Sticky Stacked Headers Enabled 󰄵", vim.log.levels.INFO)
end

--- Disable sticky stacked headers
function M.disable()
  config.options.sticky = config.options.sticky or {}
  config.options.sticky.enabled = false
  M.close_all()
  vim.notify("SuperMarkdown: Sticky Stacked Headers Disabled 󰄱", vim.log.levels.INFO)
end

--- Toggle sticky stacked headers
function M.toggle()
  if M.is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

--- Calculate stacked ancestor headings for a window that have scrolled past topline
--- @param win number Target window ID
--- @return table list of stacked heading items
function M.get_stacked_headers(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return {} end
  local target_buf = vim.api.nvim_win_get_buf(win)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then return {} end

  local ft = vim.bo[target_buf].filetype
  local is_preview = (ft == "supermarkdown_preview")
  local s_buf = target_buf

  local ok_pp, pp = pcall(require, "super-markdown.preview_pane")
  if is_preview then
    local s_opts = (config.options and config.options.sticky) or {}
    if s_opts.preview_win == false then return {} end
    if ok_pp and pp.get_source_buf then
      s_buf = pp.get_source_buf()
    end
  else
    local s_opts = (config.options and config.options.sticky) or {}
    if s_opts.source_win == false then return {} end
    if ft ~= "markdown" and ft ~= "md" and ft ~= "markdown.mdx" then
      return {}
    end
  end

  if not s_buf or not vim.api.nvim_buf_is_valid(s_buf) then return {} end
  local headings = toc.get_headings(s_buf)
  if #headings == 0 then return {} end

  local win_view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local topline = win_view.topline or 1
  local cur_lnum = vim.api.nvim_win_get_cursor(win)[1]

  local ref_lnum = math.max(topline, cur_lnum)
  if is_preview and ok_pp then
    local mapped_ref = pp.map_preview_to_source(ref_lnum)
    if mapped_ref and mapped_ref > 0 then
      ref_lnum = mapped_ref
    end
  end

  -- Build active ancestor chain up to reference line
  local chain = {}
  local cur_level = 99
  for i = #headings, 1, -1 do
    local h = headings[i]
    if h.lnum <= ref_lnum and h.level < cur_level then
      table.insert(chain, 1, h)
      cur_level = h.level
      if cur_level == 1 then break end
    end
  end

  -- Filter headings that have scrolled past topline
  local stacked = {}
  for _, h in ipairs(chain) do
    local is_past = false
    if is_preview and ok_pp then
      local p_lnum = pp.map_source_to_preview(h.lnum)
      is_past = (p_lnum and p_lnum > 0 and p_lnum < topline)
    else
      is_past = (h.lnum < topline)
    end
    if is_past then
      table.insert(stacked, h)
    end
  end

  -- Enforce max_depth (default 3)
  local max_depth = (config.options and config.options.sticky and config.options.sticky.max_depth) or 3
  if #stacked > max_depth then
    local trimmed = {}
    table.insert(trimmed, stacked[1])
    local start_idx = math.max(2, #stacked - (max_depth - 2))
    for i = start_idx, #stacked do
      table.insert(trimmed, stacked[i])
    end
    stacked = trimmed
  end

  return stacked
end

--- Update sticky stacked header float for a specific window
--- @param win number Window ID
function M.update_win(win)
  if not M.is_enabled() then
    M.close_for_win(win)
    return
  end
  if not win or not vim.api.nvim_win_is_valid(win) then
    M.close_for_win(win)
    return
  end

  local stacked = M.get_stacked_headers(win)
  if #stacked == 0 then
    M.close_for_win(win)
    return
  end

  local win_w = vim.api.nvim_win_get_width(win)
  if win_w < 12 then
    M.close_for_win(win)
    return
  end

  -- Build formatted display lines
  local lines = {}
  for idx, h in ipairs(stacked) do
    local indent = string.rep("  ", idx - 1)
    local line_str = string.format(" %s%s%s", indent, h.icon or "󰲡 ", h.title or "")
    if h.badge and h.badge ~= "" then
      line_str = line_str .. h.badge
    end
    table.insert(lines, line_str)
  end

  local has_winbar = false
  pcall(function()
    has_winbar = (vim.wo[win].winbar ~= "")
  end)
  local row = has_winbar and 1 or 0
  local height = #lines
  local show_border = (config.options and config.options.sticky and config.options.sticky.show_border ~= false)
  local border = show_border and { "", "", "", "", "─", "─", "─", "" } or "none"

  local float_data = active_floats[win]
  local fwin = float_data and float_data.float_win
  local fbuf = float_data and float_data.float_buf

  if not (fbuf and vim.api.nvim_buf_is_valid(fbuf)) then
    fbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[fbuf].buftype = "nofile"
    vim.bo[fbuf].bufhidden = "wipe"
    vim.bo[fbuf].swapfile = false
    vim.bo[fbuf].filetype = "supermarkdown_sticky"
  end

  -- Bind interactive jump when clicking or pressing Enter on a stacked header
  vim.keymap.set("n", "<CR>", function()
    local cur_row = vim.api.nvim_win_get_cursor(0)[1]
    local item = stacked[cur_row]
    if item and win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { item.lnum, 0 })
      pcall(vim.api.nvim_win_call, win, function()
        local is_top = (config.options and config.options.toc and config.options.toc.sidebar and config.options.toc.sidebar.scroll_to_top) ~= false
        vim.cmd(is_top and "normal! zvzt" or "normal! zvzz")
      end)
      pcall(vim.api.nvim_set_current_win, win)
    end
  end, { buffer = fbuf, silent = true, noremap = true })

  vim.keymap.set({ "n", "v" }, "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse and mouse.line >= 1 then
      local item = stacked[mouse.line]
      if item and win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_cursor, win, { item.lnum, 0 })
        pcall(vim.api.nvim_win_call, win, function()
          local is_top = (config.options and config.options.toc and config.options.toc.sidebar and config.options.toc.sidebar.scroll_to_top) ~= false
          vim.cmd(is_top and "normal! zvzt" or "normal! zvzz")
        end)
        pcall(vim.api.nvim_set_current_win, win)
      end
    end
  end, { buffer = fbuf, silent = true, noremap = true })

  vim.bo[fbuf].modifiable = true
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  vim.bo[fbuf].modifiable = false

  -- Styling highlights
  pcall(vim.api.nvim_buf_clear_namespace, fbuf, NS_ID, 0, -1)
  for idx, h in ipairs(stacked) do
    local line_nr = idx - 1
    local fg_hl = "SuperMarkdownH" .. (h.level or 1)
    local bg_hl = "SuperMarkdownH" .. (h.level or 1) .. "Bg"
    local indent_len = (idx - 1) * 2 + 1
    pcall(vim.api.nvim_buf_set_extmark, fbuf, NS_ID, line_nr, indent_len, {
      end_col = -1,
      hl_group = fg_hl,
      priority = 90,
    })
    if h.level <= 2 then
      pcall(vim.api.nvim_buf_set_extmark, fbuf, NS_ID, line_nr, 0, {
        line_hl_group = bg_hl,
        priority = 80,
      })
    end
  end

  local win_config = {
    relative = "win",
    win = win,
    row = row,
    col = 0,
    width = win_w,
    height = height,
    style = "minimal",
    focusable = false,
    border = border,
    zindex = 45,
  }

  if fwin and vim.api.nvim_win_is_valid(fwin) then
    pcall(vim.api.nvim_win_set_config, fwin, win_config)
  else
    local ok, nw = pcall(vim.api.nvim_open_win, fbuf, false, win_config)
    if ok and nw and vim.api.nvim_win_is_valid(nw) then
      fwin = nw
      pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:NormalFloat,FloatBorder:SuperMarkdownDivider", { win = fwin })
    end
  end

  active_floats[win] = {
    float_win = fwin,
    float_buf = fbuf,
    stacked = stacked,
  }
end

--- Close sticky header float for a specific window
--- @param win number
function M.close_for_win(win)
  local data = active_floats[win]
  if data then
    if data.float_win and vim.api.nvim_win_is_valid(data.float_win) then
      pcall(vim.api.nvim_win_close, data.float_win, true)
    end
    if data.float_buf and vim.api.nvim_buf_is_valid(data.float_buf) then
      pcall(vim.api.nvim_buf_delete, data.float_buf, { force = true })
    end
    active_floats[win] = nil
  end
end

--- Close all sticky header floats
function M.close_all()
  for w, _ in pairs(active_floats) do
    M.close_for_win(w)
  end
  active_floats = {}
end

--- Update sticky header floats across all visible markdown and preview windows
function M.update_all()
  if not M.is_enabled() then
    M.close_all()
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local b = vim.api.nvim_win_get_buf(win)
      if b and vim.api.nvim_buf_is_valid(b) then
        local ft = vim.bo[b].filetype
        if ft == "markdown" or ft == "md" or ft == "markdown.mdx" or ft == "supermarkdown_preview" then
          M.update_win(win)
        end
      end
    end
  end
end

--- Setup global autocommands for tracking window scroll and cursor movement
function M.setup_autocmds()
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end
  if not M.is_enabled() then
    return
  end

  augroup_id = vim.api.nvim_create_augroup("SuperMarkdownStickyHeaders", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
    group = augroup_id,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      M.update_win(win)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "VimResized" }, {
    group = augroup_id,
    callback = function()
      M.update_all()
    end,
  })
  vim.api.nvim_create_autocmd({ "WinClosed" }, {
    group = augroup_id,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        M.close_for_win(win)
      end
    end,
  })
end

--- Attach sticky header monitoring to a markdown buffer
--- @param bufnr number
function M.attach(bufnr)
  if M.is_enabled() then
    M.setup_autocmds()
    M.update_all()
  end
end

--- Get currently active float window for a target window (for tests / inspection)
--- @param win number
--- @return number|nil
function M.get_float_win(win)
  local data = active_floats[win]
  return (data and data.float_win and vim.api.nvim_win_is_valid(data.float_win)) and data.float_win or nil
end

return M
