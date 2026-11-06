local toc = require("super-markdown.toc")
local config = require("super-markdown.config")

local M = {}

local sidebar_win = nil
local sidebar_buf = nil
local source_buf = nil
local source_win = nil
local current_pos = nil
local headings_cache = {}
local augroup_id = nil
local NS_ID = vim.api.nvim_create_namespace("super_markdown_toc_sidebar")

function M.is_open()
  return sidebar_win ~= nil and vim.api.nvim_win_is_valid(sidebar_win)
end

function M.get_position()
  return current_pos or ((config.options.toc and config.options.toc.sidebar and config.options.toc.sidebar.position) or "right")
end

function M.set_position(pos)
  config.options.toc = config.options.toc or {}
  config.options.toc.sidebar = config.options.toc.sidebar or {}
  local cur = M.get_position()
  if not pos or pos == "" or pos == "toggle" or pos == "flip" then
    pos = (cur == "left") and "right" or "left"
  else
    pos = pos:lower()
  end
  if pos ~= "left" and pos ~= "right" then
    vim.notify("SuperMarkdown: Invalid sidebar position '" .. tostring(pos) .. "' (use 'left' or 'right')", vim.log.levels.WARN)
    return
  end
  config.options.toc.sidebar.position = pos
  current_pos = pos
  if M.is_open() then
    local was_focused = (vim.api.nvim_get_current_win() == sidebar_win)
    M.open({ position = pos, focus_sidebar = was_focused })
  end
  vim.notify("SuperMarkdown: TOC Sidebar position → " .. pos .. " 󰑐", vim.log.levels.INFO)
end

function M.get_source_buf()
  return source_buf
end

local function resolve_target_win()
  local ok_p, pp = pcall(require, "super-markdown.preview_pane")
  if ok_p and pp.is_open() then
    if not pp.is_editor_visible() then
      return pp.get_window()
    end
  end
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    return source_win
  end
  if ok_p and pp.is_open() then
    return pp.get_window()
  end
  return nil
end

function M.close()
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end
  local win_to_close = sidebar_win
  local buf_to_delete = sidebar_buf
  local prev_win = resolve_target_win()

  sidebar_win = nil
  sidebar_buf = nil
  source_buf = nil
  source_win = nil
  headings_cache = {}

  if prev_win and vim.api.nvim_win_is_valid(prev_win) and prev_win ~= win_to_close then
    pcall(vim.api.nvim_set_current_win, prev_win)
  end
  if win_to_close and vim.api.nvim_win_is_valid(win_to_close) then
    pcall(vim.api.nvim_win_close, win_to_close, true)
  end
  if buf_to_delete and vim.api.nvim_buf_is_valid(buf_to_delete) then
    pcall(vim.api.nvim_buf_delete, buf_to_delete, { force = true })
  end
end

function M.toggle(opts)
  if type(opts) == "string" and opts ~= "" then
    local arg = opts:lower()
    if arg == "flip" or arg == "switch" then
      M.set_position("toggle")
      return
    elseif arg == "left" or arg == "right" then
      if M.is_open() and M.get_position() ~= arg then
        M.set_position(arg)
        return
      end
      opts = { position = arg }
    else
      opts = {}
    end
  end
  if M.is_open() then
    M.close()
    return
  end
  M.open(opts)
end

function M.refresh()
  if not (M.is_open() and sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then
    return
  end
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then
    return
  end

  local saved_view = nil
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    pcall(function()
      saved_view = vim.api.nvim_win_call(sidebar_win, vim.fn.winsaveview)
    end)
  end

  local headings = toc.get_headings(source_buf)
  headings_cache = headings

  local auto_badge = ""
  pcall(function()
    local pp = require("super-markdown.preview_pane")
    auto_badge = pp.is_auto_refresh_enabled() and " | Auto:ON(a)" or " | Auto:OFF(a)"
  end)
  local side_badge = (M.get_position() == "left") and ("[Left | S→R" .. auto_badge .. "]") or ("[Right | S→L" .. auto_badge .. "]")
  local lines = {
    " 󰲡 TOC " .. side_badge,
    "────────────────────────────────────────",
  }
  for _, h in ipairs(headings) do
    table.insert(lines, h.display)
  end

  vim.bo[sidebar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sidebar_buf, 0, -1, false, lines)
  vim.bo[sidebar_buf].modifiable = false

  if saved_view and sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    local total_l = math.max(1, #lines)
    saved_view.lnum = math.max(1, math.min(total_l, saved_view.lnum or 1))
    saved_view.topline = math.max(1, math.min(total_l, saved_view.topline or 1))
    pcall(vim.api.nvim_win_call, sidebar_win, function()
      vim.fn.winrestview(saved_view)
    end)
  end

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

local function get_current_source_line()
  local ok_p, pp = pcall(require, "super-markdown.preview_pane")
  if ok_p and pp.is_open() and (not pp.is_editor_visible() or vim.api.nvim_get_current_win() == pp.get_window()) then
    return pp.get_active_source_line()
  end
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    return vim.api.nvim_win_get_cursor(source_win)[1]
  end
  if ok_p and pp.is_open() then
    return pp.get_active_source_line()
  end
  return 1
end

function M.sync_cursor()
  if not M.is_open() then
    return
  end
  -- Don't override sidebar highlight while user is actively browsing inside sidebar
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_get_current_win() == sidebar_win then
    return
  end

  local cursor_line = get_current_source_line()
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
    local ok_p, pp = pcall(require, "super-markdown.preview_pane")
    if ok_p and pp.is_open() then
      pp.jump_to_heading_line(target.lnum, false)
    elseif source_win and vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_win_set_cursor, source_win, { target.lnum, 0 })
      pcall(vim.api.nvim_win_call, source_win, function()
        vim.cmd("normal! zvzz")
      end)
    end

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
    local ok_p, pp = pcall(require, "super-markdown.preview_pane")
    if ok_p and pp.is_open() then
      pp.jump_to_heading_line(target.lnum, focus_editor)
    elseif source_win and vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_win_set_cursor, source_win, { target.lnum, 0 })
      pcall(vim.api.nvim_win_call, source_win, function()
        vim.cmd("normal! zvzz")
      end)
      if focus_editor then
        vim.api.nvim_set_current_win(source_win)
      end
    end

    if focus_editor then
      local s_opts = config.options.toc.sidebar or {}
      if s_opts.auto_close then
        M.close()
      end
    end
  end
end

function M.open(opts)
  if type(opts) == "string" then
    opts = { position = opts:lower() }
  else
    opts = opts or {}
  end
  M.close()

  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()
  source_buf = toc.resolve_markdown_buf(cur_buf)

  local ok_p, pp = pcall(require, "super-markdown.preview_pane")
  if ok_p and pp.is_open() and pp.get_source_win() then
    source_win = pp.get_source_win()
  elseif cur_buf == source_buf then
    source_win = cur_win
  else
    source_win = nil
  end

  local headings = toc.get_headings(source_buf)
  if #headings == 0 then
    vim.notify("SuperMarkdown: No headings found in buffer", vim.log.levels.WARN)
    return
  end
  headings_cache = headings

  local s_opts = config.options.toc.sidebar or {}
  local width = opts.width or s_opts.width or 36
  local pos = opts.position or current_pos or s_opts.position or "right"
  if pos ~= "left" and pos ~= "right" then
    pos = "right"
  end
  current_pos = pos
  s_opts.position = pos

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

  -- Position sidebar cursor at active heading corresponding to current editor/preview position
  local cursor_line = get_current_source_line()
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
    vim.keymap.set("n", key, fn, { buffer = sidebar_buf, nowait = true, silent = true, noremap = true })
  end

  local function bind_sidebar_keys()
    if not (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then return end
    set_keymap("q", M.close)
    set_keymap("Q", M.close)
    set_keymap("<Esc>", M.close)
    set_keymap("t", M.close)
    set_keymap("<leader>ms", M.close)
    set_keymap("<CR>", function() M.jump_to_heading(true) end)
    set_keymap("o", function() M.jump_to_heading(true) end)
    set_keymap("e", function()
      local ok_pp, pmod = pcall(require, "super-markdown.preview_pane")
      if ok_pp then
        pmod.toggle_editor()
      end
    end)
    set_keymap("S", function() M.set_position("toggle") end)
    set_keymap("H", function() M.set_position("left") end)
    set_keymap("L", function() M.set_position("right") end)
    set_keymap("a", function()
      local ok_pp, pmod = pcall(require, "super-markdown.preview_pane")
      if ok_pp then
        pmod.set_auto_refresh("toggle")
      end
    end)
    local km = (config.options and config.options.keymaps) or {}
    if km.auto_refresh and km.auto_refresh ~= "" then
      set_keymap(km.auto_refresh, function()
        local ok_pp, pmod = pcall(require, "super-markdown.preview_pane")
        if ok_pp then
          pmod.set_auto_refresh("toggle")
        end
      end)
    end

    -- Mouse click navigation: move focus to editor/preview at heading, keep sidebar open
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
    set_keymap("r", function()
      local ok_pp, pmod = pcall(require, "super-markdown.preview_pane")
      if ok_pp then
        pmod.check_and_refresh_buffers(true)
      else
        M.refresh()
      end
    end)
  end

  bind_sidebar_keys()

  pcall(function()
    local pp = require("super-markdown.preview_pane")
    if pp.is_auto_refresh_enabled() then
      pp.start_auto_refresh()
    end
  end)

  if opts.focus_sidebar == false and cur_win and vim.api.nvim_win_is_valid(cur_win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
  end

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
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = augroup_id,
    buffer = sidebar_buf,
    callback = function() bind_sidebar_keys() end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "BufWritePost", "BufReadPost", "FileChangedShellPost" }, {
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
