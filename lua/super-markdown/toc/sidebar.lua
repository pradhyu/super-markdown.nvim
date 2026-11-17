local toc = require("super-markdown.toc")
local config = require("super-markdown.config")

local M = {}

local sidebar_win = nil
local sidebar_buf = nil
local source_buf = nil
local source_win = nil
local current_pos = nil
local headings_cache = {}
local visible_items = {}
local collapsed_headings = {}
local collapsed_by_buf = {}
local max_level = nil
local augroup_id = nil
local global_augroup_id = nil
local buffer_augroup_id = nil
local tab_sidebars = {}
local NS_ID = vim.api.nvim_create_namespace("super_markdown_toc_sidebar")
local NS_ACTIVE = vim.api.nvim_create_namespace("super_markdown_toc_sidebar_active")

local function sync_active_sidebar_tab()
  local tab = vim.api.nvim_get_current_tabpage()
  local ts = tab_sidebars[tab]
  if ts and ts.sidebar_win and vim.api.nvim_win_is_valid(ts.sidebar_win) and vim.api.nvim_win_get_tabpage(ts.sidebar_win) == tab then
    sidebar_win = ts.sidebar_win
    sidebar_buf = ts.sidebar_buf
    source_buf = ts.source_buf
    source_win = ts.source_win
  else
    if sidebar_win and not (vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_win_get_tabpage(sidebar_win) == tab) then
      sidebar_win = nil
      sidebar_buf = nil
      source_buf = nil
      source_win = nil
    end
  end
end

function M.is_open()
  sync_active_sidebar_tab()
  local tab = vim.api.nvim_get_current_tabpage()
  local ts = tab_sidebars[tab]
  local win = (ts and ts.sidebar_win) or sidebar_win
  return win ~= nil
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_tabpage(win) == tab
end

function M.get_window()
  sync_active_sidebar_tab()
  return (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) and sidebar_win or nil
end

function M.get_buf()
  sync_active_sidebar_tab()
  return (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) and sidebar_buf or nil
end

function M.get_headings_cache()
  return headings_cache
end

function M.get_visible_items()
  return visible_items
end

function M.is_collapsed(src_lnum)
  return collapsed_headings[src_lnum] == true
end

function M.set_collapsed(src_lnum, collapsed)
  if collapsed then
    collapsed_headings[src_lnum] = true
  else
    collapsed_headings[src_lnum] = nil
  end
  if source_buf then
    collapsed_by_buf[source_buf] = collapsed_headings
  end
end

function M.get_item_at_row(row)
  row = row or (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_win_get_cursor(sidebar_win)[1])
  if not row then return nil end
  local idx = row - 2
  return visible_items[idx]
end

function M.is_scroll_to_top()
  local s_opts = (config.options and config.options.toc and config.options.toc.sidebar) or {}
  return s_opts.scroll_to_top ~= false
end

function M.set_scroll_to_top(val)
  config.options.toc = config.options.toc or {}
  config.options.toc.sidebar = config.options.toc.sidebar or {}
  if val == nil or val == "toggle" then
    config.options.toc.sidebar.scroll_to_top = not M.is_scroll_to_top()
  else
    config.options.toc.sidebar.scroll_to_top = (val == true or val == "top" or val == 1)
  end
  local mode_str = M.is_scroll_to_top() and "Top (zt)" or "Center (zz)"
  if M.is_open() then
    M.refresh()
  end
  vim.notify("SuperMarkdown: TOC scroll position ➔ " .. mode_str .. " 󰉋", vim.log.levels.INFO)
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
  sync_active_sidebar_tab()
  return source_buf
end

function M.get_source_win()
  sync_active_sidebar_tab()
  return (source_win and vim.api.nvim_win_is_valid(source_win)) and source_win or nil
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
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    local wins = vim.fn.win_findbuf(source_buf)
    for _, w in ipairs(wins) do
      if w ~= sidebar_win and vim.api.nvim_win_is_valid(w) then
        return w
      end
    end
  end
  if ok_p and pp.is_open() then
    return pp.get_window()
  end
  return nil
end

local function attach_source_buf_autocmds()
  local tab = vim.api.nvim_get_current_tabpage()
  local ts = tab_sidebars[tab]
  if ts and ts.buffer_augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, ts.buffer_augroup_id)
    ts.buffer_augroup_id = nil
  end
  if buffer_augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, buffer_augroup_id)
    buffer_augroup_id = nil
  end
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then
    return
  end
  buffer_augroup_id = vim.api.nvim_create_augroup("SuperMarkdownTocSidebarBufTab_" .. tab .. "_" .. source_buf, { clear = true })
  if ts then
    ts.buffer_augroup_id = buffer_augroup_id
  end
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorHold" }, {
    group = buffer_augroup_id,
    buffer = source_buf,
    callback = function() M.sync_cursor() end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = buffer_augroup_id,
    buffer = source_buf,
    callback = function() M.debounced_refresh(100) end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "FileChangedShellPost" }, {
    group = buffer_augroup_id,
    buffer = source_buf,
    callback = function() M.refresh() end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = buffer_augroup_id,
    buffer = source_buf,
    callback = function()
      -- If another markdown buffer is visible in any window, switch to it; otherwise close
      local found_buf = nil
      local found_win = nil
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= sidebar_win and vim.api.nvim_win_is_valid(w) then
          local b = vim.api.nvim_win_get_buf(w)
          local tb = toc.resolve_markdown_buf(b)
          if tb ~= source_buf and toc.is_markdown_buf(tb) then
            found_buf = tb
            found_win = w
            break
          end
        end
      end
      if found_buf then
        M.switch_source(found_buf, found_win)
      else
        M.close()
      end
    end,
  })
end

function M.switch_source(new_buf, new_win)
  if not M.is_open() then
    return
  end
  if not new_buf or not vim.api.nvim_buf_is_valid(new_buf) then
    return
  end
  local target_buf = toc.resolve_markdown_buf(new_buf)
  if not toc.is_markdown_buf(target_buf) then
    return
  end
  if target_buf == source_buf and (not new_win or new_win == source_win) then
    return
  end

  source_buf = target_buf
  if new_win and vim.api.nvim_win_is_valid(new_win) and new_win ~= sidebar_win then
    source_win = new_win
  else
    source_win = resolve_target_win()
  end

  local tab = vim.api.nvim_get_current_tabpage()
  if tab_sidebars[tab] then
    tab_sidebars[tab].source_buf = source_buf
    tab_sidebars[tab].source_win = source_win
  end

  if not collapsed_by_buf[source_buf] then
    collapsed_by_buf[source_buf] = {}
  end
  collapsed_headings = collapsed_by_buf[source_buf]

  attach_source_buf_autocmds()
  M.refresh()
  M.sync_cursor()
end

function M.close()
  local tab = vim.api.nvim_get_current_tabpage()
  local ts = tab_sidebars[tab]
  if ts then
    if ts.global_augroup_id then
      pcall(vim.api.nvim_del_augroup_by_id, ts.global_augroup_id)
    end
    if ts.buffer_augroup_id then
      pcall(vim.api.nvim_del_augroup_by_id, ts.buffer_augroup_id)
    end
    tab_sidebars[tab] = nil
  else
    if global_augroup_id then
      pcall(vim.api.nvim_del_augroup_by_id, global_augroup_id)
      global_augroup_id = nil
    end
    if buffer_augroup_id then
      pcall(vim.api.nvim_del_augroup_by_id, buffer_augroup_id)
      buffer_augroup_id = nil
    end
    if augroup_id then
      pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
      augroup_id = nil
    end
  end

  local win_to_close = (ts and ts.sidebar_win) or sidebar_win
  local buf_to_delete = (ts and ts.sidebar_buf) or sidebar_buf
  local prev_win = resolve_target_win()

  sidebar_win = nil
  sidebar_buf = nil
  source_buf = nil
  source_win = nil
  headings_cache = {}
  visible_items = {}
  collapsed_headings = {}
  max_level = nil

  if refresh_timer then
    pcall(function()
      refresh_timer:stop()
      refresh_timer:close()
    end)
    refresh_timer = nil
  end

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
    local cur_win = vim.api.nvim_get_current_win()
    local cur_buf = vim.api.nvim_win_get_buf(cur_win)
    if cur_win ~= sidebar_win and cur_buf ~= sidebar_buf then
      local ok_t, toc = pcall(require, "super-markdown.toc")
      local resolved = ok_t and toc.resolve_markdown_buf(cur_buf) or cur_buf
      if resolved and resolved ~= source_buf and ok_t and toc.is_markdown_buf(resolved) then
        M.switch_source(resolved, cur_win)
        vim.notify("SuperMarkdown: TOC switched to active buffer 󰄵", vim.log.levels.INFO)
        return
      end
    end
    M.close()
    return
  end
  M.open(opts)
end

local refresh_timer = nil

function M.debounced_refresh(delay_ms)
  delay_ms = delay_ms or 100
  if refresh_timer then
    pcall(function()
      refresh_timer:stop()
      refresh_timer:close()
    end)
    refresh_timer = nil
  end
  refresh_timer = vim.uv.new_timer()
  refresh_timer:start(
    delay_ms,
    0,
    vim.schedule_wrap(function()
      if refresh_timer then
        pcall(function()
          refresh_timer:stop()
          refresh_timer:close()
        end)
        refresh_timer = nil
      end
      if M.is_open() then
        M.refresh()
      end
    end)
  )
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

  if not collapsed_by_buf[source_buf] then
    collapsed_by_buf[source_buf] = {}
  end
  collapsed_headings = collapsed_by_buf[source_buf]

  -- Compute tree structure: child presence and descendant counts
  for i = 1, #headings do
    local cur_h = headings[i]
    cur_h.has_children = false
    cur_h.descendant_count = 0
    cur_h.descendants = {}
    for j = i + 1, #headings do
      if headings[j].level > cur_h.level then
        cur_h.has_children = true
        cur_h.descendant_count = cur_h.descendant_count + 1
        table.insert(cur_h.descendants, headings[j].lnum)
      else
        break
      end
    end
  end

  -- Filter visible items taking collapsed state and max_level into account
  visible_items = {}
  local skip_until_level = nil
  for _, h in ipairs(headings) do
    if skip_until_level then
      if h.level <= skip_until_level then
        skip_until_level = nil
      end
    end

    if not skip_until_level then
      if not max_level or h.level <= max_level then
        local is_col = collapsed_headings[h.lnum] == true
        local indent = string.rep("  ", h.level - 1)
        local fold_sym = "  "
        local suffix = ""
        if h.has_children then
          if is_col then
            fold_sym = "▸ "
            suffix = string.format(" ⋯ (+%d)", h.descendant_count)
          else
            fold_sym = "▾ "
          end
        end

        local title_str = h.title or ""
        local badge_str = h.badge or ""
        local rendered_line = string.format("%s%s%s%s%s%s", indent, fold_sym, h.icon, title_str, badge_str, suffix)
        table.insert(visible_items, {
          heading = h,
          is_collapsed = is_col,
          has_children = h.has_children,
          descendant_count = h.descendant_count,
          rendered_line = rendered_line,
          indent = indent,
          fold_sym = fold_sym,
          suffix = suffix,
        })

        if is_col and h.has_children then
          skip_until_level = h.level
        end
      end
    end
  end

  local auto_badge = ""
  pcall(function()
    local pp = require("super-markdown.preview_pane")
    auto_badge = pp.is_auto_refresh_enabled() and " | Auto:ON(a)" or " | Auto:OFF(a)"
  end)
  local top_badge = M.is_scroll_to_top() and "Top(z)" or "Ctr(z)"
  local side_badge = (M.get_position() == "left") and ("[Left | " .. top_badge .. " | S→R" .. auto_badge .. "]") or ("[Right | " .. top_badge .. " | S→L" .. auto_badge .. "]")
  local lines = {
    " 󰲡 TOC " .. side_badge,
    "────────────────────────────────────────",
  }
  if #visible_items == 0 then
    table.insert(lines, "  (No headings in document)")
  else
    for _, item in ipairs(visible_items) do
      table.insert(lines, item.rendered_line)
    end
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

  -- Heading rows styling: match exact colors used in Markdown rendering
  pcall(vim.api.nvim_buf_clear_namespace, sidebar_buf, NS_ID, 2, -1)
  for idx, item in ipairs(visible_items) do
    local h = item.heading
    local line_nr = idx + 1 -- accounting for 2 header lines
    local fg_hl = "SuperMarkdownH" .. h.level
    local bg_hl = "SuperMarkdownH" .. h.level .. "Bg"

    local line_text = item.rendered_line or ""
    local indent_len = #item.indent
    local start_col = indent_len
    local badge_idx = line_text:find("%s+%[")
    local suffix_idx = line_text:find("%s+⋯")
    local title_end = badge_idx and (badge_idx - 1) or (suffix_idx and (suffix_idx - 1) or #line_text)

    -- 1. Highlight heading icon and title with exact level color
    pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, line_nr, start_col, {
      end_col = title_end,
      hl_group = fg_hl,
      priority = 90,
    })

    -- 2. Highlight badge components with comment/badge style
    if badge_idx then
      local badge_end = suffix_idx and (suffix_idx - 1) or #line_text
      pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, line_nr, badge_idx, {
        end_col = badge_end,
        hl_group = "Comment",
        priority = 85,
      })
    end

    -- 3. Highlight collapsed suffix count with subtle comment style
    if suffix_idx then
      pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, line_nr, suffix_idx, {
        end_col = #line_text,
        hl_group = "Comment",
        priority = 85,
      })
    end

    -- 4. Level 1 & 2 subtle background banner matching Markdown rendering
    if h.level <= 2 then
      pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ID, line_nr, 0, {
        line_hl_group = bg_hl,
        priority = 80,
      })
    end
  end

  M.sync_cursor(true)
end

local last_synced_line = nil
local last_active_idx = nil
local last_preview_row = nil

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

function M.sync_cursor(force)
  if not M.is_open() then
    return
  end
  if force then
    last_synced_line = nil
    last_active_idx = nil
    last_preview_row = nil
  end
  -- Don't override sidebar highlight while user is actively browsing inside sidebar
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) and vim.api.nvim_get_current_win() == sidebar_win then
    return
  end

  local cursor_line = get_current_source_line()
  if not force and cursor_line == last_synced_line then
    return
  end
  last_synced_line = cursor_line

  local active_idx = nil

  for idx, item in ipairs(visible_items) do
    if item.heading.lnum <= cursor_line then
      active_idx = idx
    else
      break
    end
  end

  if active_idx and sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf) then
    if not force and active_idx == last_active_idx then
      return
    end
    last_active_idx = active_idx
    pcall(vim.api.nvim_buf_clear_namespace, sidebar_buf, NS_ACTIVE, 0, -1)
    local target_line = active_idx + 1 -- accounting for 2 header lines
    pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ACTIVE, target_line, 0, {
      line_hl_group = "SuperMarkdownTocActive",
      priority = 100,
    })
  end
end

function M.preview_heading()
  if not (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) then return end
  if not (sidebar_buf and vim.api.nvim_buf_is_valid(sidebar_buf)) then return end
  if #visible_items == 0 then return end

  local cursor_row = vim.api.nvim_win_get_cursor(sidebar_win)[1]
  if cursor_row == last_preview_row then
    return
  end
  last_preview_row = cursor_row
  last_active_idx = nil
  local heading_idx = cursor_row - 2
  if heading_idx < 1 then
    heading_idx = 1
  end
  if heading_idx > #visible_items then
    heading_idx = #visible_items
  end

  local item = visible_items[heading_idx]
  local target = item and item.heading
  if target then
    local is_top = M.is_scroll_to_top()
    local view_cmd = is_top and "normal! zvzt" or "normal! zvzz"
    local ok_p, pp = pcall(require, "super-markdown.preview_pane")
    if ok_p and pp.is_open() then
      pp.jump_to_heading_line(target.lnum, false, is_top)
    elseif source_win and vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_win_set_cursor, source_win, { target.lnum, 0 })
      pcall(vim.api.nvim_win_call, source_win, function()
        vim.cmd(view_cmd)
      end)
    end

    pcall(vim.api.nvim_buf_clear_namespace, sidebar_buf, NS_ACTIVE, 0, -1)
    local hl_line = math.max(2, cursor_row - 1)
    pcall(vim.api.nvim_buf_set_extmark, sidebar_buf, NS_ACTIVE, hl_line, 0, {
      line_hl_group = "SuperMarkdownTocActive",
      priority = 100,
    })
  end
end

function M.jump_to_heading(focus_editor)
  if not (sidebar_win and vim.api.nvim_win_is_valid(sidebar_win)) then return end
  if #visible_items == 0 then return end

  local cursor_row = vim.api.nvim_win_get_cursor(sidebar_win)[1]
  local heading_idx = cursor_row - 2 -- accounting for 2 header lines
  if heading_idx < 1 then
    heading_idx = 1
  end
  if heading_idx > #visible_items then
    heading_idx = #visible_items
  end

  local item = visible_items[heading_idx]
  local target = item and item.heading
  if target then
    local is_top = M.is_scroll_to_top()
    local view_cmd = is_top and "normal! zvzt" or "normal! zvzz"
    local target_w = resolve_target_win()
    if ok_p and pp.is_open() then
      pp.jump_to_heading_line(target.lnum, focus_editor, is_top)
    elseif target_w and vim.api.nvim_win_is_valid(target_w) then
      pcall(vim.api.nvim_win_set_cursor, target_w, { target.lnum, 0 })
      pcall(vim.api.nvim_win_call, target_w, function()
        vim.cmd(view_cmd)
      end)
      if focus_editor then
        vim.api.nvim_set_current_win(target_w)
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

  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()
  local resolved_buf = toc.resolve_markdown_buf(cur_buf)

  if M.is_open() then
    if resolved_buf and resolved_buf ~= source_buf and toc.is_markdown_buf(resolved_buf) then
      M.switch_source(resolved_buf, cur_win)
      return
    end
    M.close()
  end

  source_buf = resolved_buf

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

  if not collapsed_by_buf[source_buf] then
    collapsed_by_buf[source_buf] = {}
  end
  collapsed_headings = collapsed_by_buf[source_buf]

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
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = sidebar_win })
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

  local tab = vim.api.nvim_get_current_tabpage()
  tab_sidebars[tab] = {
    sidebar_win = sidebar_win,
    sidebar_buf = sidebar_buf,
    source_buf = source_buf,
    source_win = source_win,
  }

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

    -- Vim folding keybindings adhering to Neovim fold conventions
    set_keymap("za", function() M.toggle_header() end)
    set_keymap("<Space>", function() M.toggle_header() end)
    set_keymap("zc", function() M.collapse_header() end)
    set_keymap("-", function() M.collapse_header() end)
    set_keymap("zo", function() M.expand_header() end)
    set_keymap("+", function() M.expand_header() end)
    set_keymap("zM", function() M.collapse_all() end)
    set_keymap("zR", function() M.expand_all() end)
    set_keymap("zm", function() M.fold_more() end)
    set_keymap("zr", function() M.fold_less() end)

    -- Toggle positioning header at top of view (zt) vs center (zz)
    set_keymap("z", function() M.set_scroll_to_top("toggle") end)
    set_keymap("Z", function() M.set_scroll_to_top("toggle") end)

    -- Toggle Sticky Stacked Headers from sidebar
    set_keymap("<leader>mH", function() require("super-markdown.sticky").toggle() end)
    set_keymap("X", function() require("super-markdown.sticky").toggle() end)
  end

  bind_sidebar_keys()

  local focus_sb = opts.focus_sidebar
  if focus_sb == nil then
    local s_opts = (config.options and config.options.toc and config.options.toc.sidebar) or {}
    focus_sb = s_opts.focus_on_open ~= false
  end
  if not focus_sb and cur_win and vim.api.nvim_win_is_valid(cur_win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
  end

  -- Global autocommands for document tracking and sidebar buffer
  local tab = vim.api.nvim_get_current_tabpage()
  global_augroup_id = vim.api.nvim_create_augroup("SuperMarkdownTocSidebarTab_" .. tab, { clear = true })
  augroup_id = global_augroup_id
  if tab_sidebars[tab] then
    tab_sidebars[tab].global_augroup_id = global_augroup_id
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "BufWinEnter" }, {
    group = global_augroup_id,
    callback = function(args)
      if not M.is_open() then return end
      local win = vim.api.nvim_get_current_win()
      local buf = args.buf
      if not buf or not vim.api.nvim_buf_is_valid(buf) or buf == 0 then
        buf = vim.api.nvim_win_get_buf(win)
      end
      if buf == sidebar_buf then return end
      local ok_p, pp = pcall(require, "super-markdown.preview_pane")
      if ok_p and buf == pp.get_buffer() then return end

      local s_opts = (config.options and config.options.toc and config.options.toc.sidebar) or {}
      if s_opts.auto_switch_buffer == false then return end

      local target_buf = toc.resolve_markdown_buf(buf)
      if toc.is_markdown_buf(target_buf) then
        if target_buf ~= source_buf then
          M.switch_source(target_buf, win)
        elseif win ~= source_win and vim.api.nvim_win_is_valid(win) then
          source_win = win
          M.sync_cursor()
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = global_augroup_id,
    buffer = sidebar_buf,
    callback = function() M.preview_heading() end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = global_augroup_id,
    buffer = sidebar_buf,
    callback = function() bind_sidebar_keys() end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = global_augroup_id,
    buffer = sidebar_buf,
    callback = function()
      sidebar_buf = nil
      M.close()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = global_augroup_id,
    pattern = tostring(sidebar_win),
    callback = function() M.close() end,
  })

  attach_source_buf_autocmds()
end

function M.collapse_header(target_lnum)
  local folds_mod = require("super-markdown.folds")
  folds_mod.collapse_header(target_lnum)
end

function M.expand_header(target_lnum)
  local folds_mod = require("super-markdown.folds")
  folds_mod.expand_header(target_lnum)
end

function M.toggle_header(target_lnum)
  local folds_mod = require("super-markdown.folds")
  folds_mod.toggle_header(target_lnum)
end

function M.collapse_all()
  local folds_mod = require("super-markdown.folds")
  folds_mod.collapse_all()
end

function M.expand_all()
  local folds_mod = require("super-markdown.folds")
  folds_mod.expand_all()
end

function M.fold_more()
  local folds_mod = require("super-markdown.folds")
  folds_mod.fold_more()
end

function M.fold_less()
  local folds_mod = require("super-markdown.folds")
  folds_mod.fold_less()
end

function M.collapse_all_internal()
  for _, h in ipairs(headings_cache) do
    if h.has_children then
      collapsed_headings[h.lnum] = true
    end
  end
  if source_buf then
    collapsed_by_buf[source_buf] = collapsed_headings
  end
  M.refresh()
end

function M.expand_all_internal()
  collapsed_headings = {}
  if source_buf then
    collapsed_by_buf[source_buf] = collapsed_headings
  end
  max_level = nil
  M.refresh()
end

function M.fold_more_internal()
  local deepest = 0
  for _, item in ipairs(visible_items) do
    if item.has_children and not item.is_collapsed then
      if item.heading.level > deepest then
        deepest = item.heading.level
      end
    end
  end
  if deepest > 0 then
    for _, item in ipairs(visible_items) do
      if item.heading.level == deepest and item.has_children and not item.is_collapsed then
        collapsed_headings[item.heading.lnum] = true
      end
    end
  elseif #visible_items > 0 then
    local cur_max = max_level or 6
    if cur_max > 1 then
      max_level = cur_max - 1
    end
  end
  if source_buf then
    collapsed_by_buf[source_buf] = collapsed_headings
  end
  M.refresh()
end

function M.fold_less_internal()
  if max_level and max_level < 6 then
    max_level = max_level + 1
    M.refresh()
    return
  end
  local shallowest = 99
  for _, h in ipairs(headings_cache) do
    if collapsed_headings[h.lnum] and h.level < shallowest then
      shallowest = h.level
    end
  end
  if shallowest < 99 then
    for _, h in ipairs(headings_cache) do
      if h.level == shallowest and collapsed_headings[h.lnum] then
        collapsed_headings[h.lnum] = nil
      end
    end
  end
  if source_buf then
    collapsed_by_buf[source_buf] = collapsed_headings
  end
  M.refresh()
end

return M
