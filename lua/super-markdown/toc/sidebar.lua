local toc = require("super-markdown.toc")
local config = require("super-markdown.config")

local M = {}

local sidebar_win = nil
local sidebar_buf = nil
local source_buf = nil
local source_win = nil
local headings_cache = {}
local augroup_id = nil
local NS_ID = vim.api.nvim_create_namespace("super_markdown_toc_sidebar")

function M.is_open()
  return sidebar_win ~= nil and vim.api.nvim_win_is_valid(sidebar_win)
end

function M.close()
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end
  if M.is_open() then
    pcall(vim.api.nvim_win_close, sidebar_win, true)
  end
  sidebar_win = nil
  sidebar_buf = nil
  source_buf = nil
  source_win = nil
  headings_cache = {}
end

function M.toggle()
  if M.is_open() then
    M.close()
    return
  end
  M.open()
end

function M.refresh()
  if not (M.is_open() and sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then
    return
  end
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then
    return
  end

  local headings = toc.get_headings(source_buf)
  headings_cache = headings

  local lines = {
    " 󰲡 Table of Contents",
    "────────────────────────────────────────",
  }
  for _, h in ipairs(headings) do
    table.insert(lines, h.display)
  end

  vim.bo[sidebar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
  vim.bo[sidebar_buf].modifiable = false

  -- Header styling
  pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, 0, 0, {
    line_hl_group = "SuperMarkdownTocTitle",
    priority = 100,
  })
  pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, 1, 0, {
    line_hl_group = "SuperMarkdownDivider",
    priority = 100,
  })

  M.sync_cursor()
end

function M.sync_cursor()
  if not M.is_open() or not (source_win and vim.api.nvim_win_is_valid(source_win)) then
    return
  end
  -- Don't override sidebar highlight while user is actively browsing inside sidebar
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_get_current_win() == sidebar_win then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1]
  local active_idx = nil

  for i, h in ipairs(headings_cache) do
    if h.lnum <= cursor_line then
      active_idx = i
    else
      break
    end
  end

  if active_idx and sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf) then
    vim.api.nvim_buf_clear_namespace(sidebar_buf, NS_ID, 2, -1)
    local target_line = active_idx + 1 -- accounting for 2 header lines
    pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, target_line, 0, {
      line_hl_group = "SuperMarkdownTocActive",
      priority = 100,
    })
  end
end

function M.preview_heading()
  if not (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) then return end
  if not (source_win and vim.api.nvim_win_is_valid(source_win)) then return end
  if not (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then return end
  if #headings_cache == 0 then return end

  local cursor_row = vim.api.nvim_win_get_cursor(sidebar_win)[1]
  local heading_idx = cursor_row - 2
  if heading_idx < 1 then
    heading_idx = 1
  end
  if heading_idx > #headings_cache then
    heading_idx = #headings_cache
  end

  local target = headings_cache[heading_idx]
  if target then
    pcall(vim.api.nvim_win_set_cursor, source_win, { target.lnum, 0 })
    pcall(vim.api.nvim_win_call, source_win, function()
      vim.cmd("normal! zvzz")
    end)

    pcall(vim.api.nvim_buf_clear_namespace, sidebar_buf, NS_ID, 2, -1)
    local hl_line = math.max(2, cursor_row - 1)
    pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, hl_line, 0, {
      line_hl_group = "SuperMarkdownTocActive",
      priority = 100,
    })
  end
end

function M.jump_to_heading(focus_editor)
  if not (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) then return end
  if not (source_win and vim.api.nvim_win_is_valid(source_win)) then return end
  if #headings_cache == 0 then return end

  local cursor_row = vim.api.nvim_win_get_cursor(sidebar_win)[1]
  local heading_idx = cursor_row - 2 -- accounting for 2 header lines
  if heading_idx < 1 then
    heading_idx = 1
  end
  if heading_idx > #headings_cache then
    heading_idx = #headings_cache
  end

  local target = headings_cache[heading_idx]
  if target then
    pcall(vim.api.nvim_win_set_cursor, source_win, { target.lnum, 0 })
    pcall(vim.api.nvim_win_call, source_win, function()
      vim.cmd("normal! zvzz")
    end)

    if focus_editor then
      vim.api.nvim_set_current_win(source_win)
      local s_opts = config.options.toc.sidebar or {}
      if s_opts.auto_close then
        M.close()
      end
    end
  end
end

function M.open()
  M.close()

  source_buf = vim.api.nvim_get_current_buf()
  source_win = vim.api.nvim_get_current_win()

  local headings = toc.get_headings(source_buf)
  if #headings == 0 then
    vim.notify("SuperMarkdown: No headings found in buffer", vim.log.levels.WARN)
    return
  end
  headings_cache = headings

  local s_opts = config.options.toc.sidebar or {}
  local width = s_opts.width or 36
  local pos = s_opts.position or "right"

  -- Create fixed vertical split window
  local split_cmd = (pos == "left") and ("topleft vertical " .. width .. " split") or ("botright vertical " .. width .. " split")
  vim.cmd(split_cmd)

  sidebar_win = vim.api.nvim_get_current_win()
  sidebar_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)

  -- Window options
  pcall(vim.api.nvim_set_option_value, "winfixwidth", true, { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "number", false, { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", "0", { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "wrap", false, { win = sidebar_win })
  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = sidebar_win })

  -- Buffer options
  vim.bo[sidebar_buf].buftype = "nofile"
  vim.bo[sidebar_buf].bufhidden = "wipe"
  vim.bo[sidebar_buf].swapfile = false
  vim.bo[sidebar_buf].filetype = "supermarkdown_toc"

  M.refresh()

  -- Position sidebar cursor at active heading corresponding to current editor position
  local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1]
  local initial_idx = 1
  for i, h in ipairs(headings_cache) do
    if h.lnum <= cursor_line then
      initial_idx = i
    else
      break
    end
  end
  local target_sidebar_row = initial_idx + 2
  pcall(vim.api.nvim_win_set_cursor, sidebar_win, { target_sidebar_row, 0 })

  -- Keybindings inside sidebar
  local set_keymap = function(key, fn)
    vim.keymap.set("n", key, fn, { buffer = sidebar_buf, nowait = true, silent = true })
  end

  set_keymap("q", M.close)
  set_keymap("<Esc>", M.close)
  set_keymap("<CR>", function() M.jump_to_heading(true) end)
  set_keymap("o", function() M.jump_to_heading(true) end)

  -- Mouse click navigation: move focus to editor at heading, keep sidebar open
  set_keymap("<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == sidebar_win and mouse.line > 2 then
      pcall(vim.api.nvim_win_set_cursor, sidebar_win, { mouse.line, 0 })
      M.jump_to_heading(true)
    end
  end)
  set_keymap("<2-LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == sidebar_win and mouse.line > 2 then
      pcall(vim.api.nvim_win_set_cursor, sidebar_win, { mouse.line, 0 })
      M.jump_to_heading(true)
    end
  end)

  set_keymap("<Tab>", function() M.jump_to_heading(false) end)
  set_keymap("p", function() M.jump_to_heading(false) end)
  set_keymap("r", M.refresh)

  -- Autocommands for live sync and auto-refresh
  augroup_id = vim.api.nvim_create_augroup("SuperMarkdownTocSidebar_" .. source_buf, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold" }, {
    group = augroup_id,
    buffer = source_buf,
    callback = function() M.sync_cursor() end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup_id,
    buffer = sidebar_buf,
    callback = function() M.preview_heading() end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "BufWritePost" }, {
    group = augroup_id,
    buffer = source_buf,
    callback = function() M.refresh() end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup_id,
    buffer = source_buf,
    callback = function() M.close() end,
  })
end

return M
