local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local NS_DIFF = vim.api.nvim_create_namespace("super_markdown_spec_diff")
local diff_states = {} -- bufnr -> { enabled = bool, hunks = {}, stats = {} }
local dash_win = nil
local dash_buf = nil

--- Pure Lua Longest Common Subsequence line diff fallback
--- @param old_lines string[]
--- @param new_lines string[]
--- @return table hunks, table stats
local function lua_line_diff(old_lines, new_lines)
  local hunks = {}
  local stats = { added = 0, modified = 0, deleted = 0 }
  local o_len = #old_lines
  local n_len = #new_lines

  local o_idx = 1
  local n_idx = 1

  while o_idx <= o_len or n_idx <= n_len do
    if o_idx <= o_len and n_idx <= n_len and old_lines[o_idx] == new_lines[n_idx] then
      o_idx = o_idx + 1
      n_idx = n_idx + 1
    else
      local o_start = o_idx
      local n_start = n_idx

      -- Find next matching line anchor
      local found_o, found_n = nil, nil
      for lookahead = 1, 50 do
        for di = 0, lookahead do
          local oi = o_start + di
          local ni = n_start + (lookahead - di)
          if oi <= o_len and ni <= n_len and old_lines[oi] == new_lines[ni] then
            found_o = oi
            found_n = ni
            break
          end
        end
        if found_o then break end
      end

      local o_end = found_o and (found_o - 1) or o_len
      local n_end = found_n and (found_n - 1) or n_len

      local del_count = math.max(0, o_end - o_start + 1)
      local add_count = math.max(0, n_end - n_start + 1)

      local h_type = "change"
      if del_count == 0 and add_count > 0 then
        h_type = "add"
        stats.added = stats.added + add_count
      elseif add_count == 0 and del_count > 0 then
        h_type = "delete"
        stats.deleted = stats.deleted + del_count
      else
        stats.modified = stats.modified + math.max(add_count, del_count)
      end

      local old_hunk_lines = {}
      for i = o_start, o_end do
        table.insert(old_hunk_lines, old_lines[i])
      end
      local new_hunk_lines = {}
      for i = n_start, n_end do
        table.insert(new_hunk_lines, new_lines[i])
      end

      table.insert(hunks, {
        type = h_type,
        start_line = math.max(1, n_start),
        end_line = math.max(n_start, n_end),
        old_count = del_count,
        new_count = add_count,
        old_lines = old_hunk_lines,
        new_lines = new_hunk_lines,
      })

      o_idx = o_end + 1
      n_idx = n_end + 1
    end
  end

  return hunks, stats
end

--- Extract diff against git HEAD or fallback
--- @param bufnr number
--- @param base_ref? string (e.g. "HEAD")
--- @return table hunks, table stats
function M.compute_diff(bufnr, base_ref)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return {}, { added = 0, modified = 0, deleted = 0 }
  end

  base_ref = base_ref or "HEAD"
  local cur_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Try git diff if inside git repo
  local dir = vim.fs.dirname(file_path)
  local is_git = vim.fn.system(string.format("git -C %s rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(dir))):match("true")

  if is_git then
    local rel_path = vim.fn.system(string.format("git -C %s ls-files --full-name %s 2>/dev/null", vim.fn.shellescape(dir), vim.fn.shellescape(file_path))):gsub("%s+$", "")
    if rel_path ~= "" then
      -- Get HEAD version of the file
      local old_content = vim.fn.system(string.format("git -C %s show %s:%s 2>/dev/null", vim.fn.shellescape(dir), base_ref, vim.fn.shellescape(rel_path)))
      if vim.v.shell_error == 0 then
        local old_lines = vim.split(old_content, "\n", { plain = true })
        if old_lines[#old_lines] == "" then
          table.remove(old_lines, #old_lines)
        end
        return lua_line_diff(old_lines, cur_lines)
      end
    end
  end

  -- Fallback: compare with saved file on disk if buffer is modified
  if vim.fn.filereadable(file_path) == 1 then
    local disk_lines = vim.fn.readfile(file_path)
    return lua_line_diff(disk_lines, cur_lines)
  end

  return {}, { added = 0, modified = 0, deleted = 0 }
end

--- Get diff stats aggregated by section heading
--- @param bufnr number
--- @return table<number, table> section_diffs (heading_lnum -> { added, modified, deleted })
function M.get_section_diffs(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local hunks, _ = M.compute_diff(bufnr)
  local analysis = analyzer.analyze(bufnr)
  local sections = analysis.sections or {}
  local sec_diffs = {}

  if #sections == 0 then
    return sec_diffs
  end

  for _, s in ipairs(sections) do
    sec_diffs[s.lnum] = { added = 0, modified = 0, deleted = 0, count = 0 }
  end

  for _, h in ipairs(hunks) do
    -- Find which section this hunk belongs to
    local target_sec = nil
    for _, s in ipairs(sections) do
      if h.start_line >= s.lnum and h.start_line <= s.end_lnum then
        target_sec = s
        break
      end
    end

    if target_sec then
      local sd = sec_diffs[target_sec.lnum]
      if sd then
        if h.type == "add" then
          sd.added = sd.added + h.new_count
        elseif h.type == "delete" then
          sd.deleted = sd.deleted + h.old_count
        else
          sd.modified = sd.modified + math.max(h.new_count, h.old_count)
        end
        sd.count = sd.count + 1
      end
    end
  end

  return sec_diffs
end

--- Render live diff indicators in buffer
--- @param bufnr number
function M.render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, NS_DIFF, 0, -1)

  local hunks, stats = M.compute_diff(bufnr)
  diff_states[bufnr] = { enabled = true, hunks = hunks, stats = stats }

  if #hunks == 0 then
    return
  end

  for _, h in ipairs(hunks) do
    local s_line = math.max(0, h.start_line - 1)
    local e_line = math.max(s_line, h.end_line - 1)

    if h.type == "add" then
      -- Subtle green gutter sign + inline badge
      for l = s_line, e_line do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_DIFF, l, 0, {
          sign_text = "▎+",
          sign_hl_group = "DiagnosticOk",
          priority = 90,
        })
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_DIFF, s_line, 0, {
        virt_text = { { string.format(" 󰜥 +%d Added", h.new_count), "DiagnosticOk" } },
        virt_text_pos = "eol",
        priority = 90,
      })
    elseif h.type == "change" then
      -- Subtle amber gutter sign + inline badge
      for l = s_line, e_line do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_DIFF, l, 0, {
          sign_text = "▎~",
          sign_hl_group = "DiagnosticWarn",
          priority = 90,
        })
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_DIFF, s_line, 0, {
        virt_text = { { string.format(" 󰜥 ~%d Modified", h.new_count), "DiagnosticWarn" } },
        virt_text_pos = "eol",
        priority = 90,
      })
    elseif h.type == "delete" then
      -- Ghost line indicator for deleted lines
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_DIFF, s_line, 0, {
        sign_text = "▎-",
        sign_hl_group = "DiagnosticError",
        virt_lines = {
          { { string.format("  ▾ %d line(s) deleted here (agent change)", h.old_count), "Comment" } },
        },
        virt_lines_above = true,
        priority = 90,
      })
    end
  end
end

--- Clear diff indicators
--- @param bufnr number
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, NS_DIFF, 0, -1)
  if diff_states[bufnr] then
    diff_states[bufnr].enabled = false
  end
end

--- Toggle diff indicators
--- @param bufnr number
--- @return boolean new_state
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = diff_states[bufnr]
  if st and st.enabled then
    M.clear(bufnr)
    vim.notify("SuperMarkdown Spec Diff: Disabled 󰄱", vim.log.levels.INFO)
    return false
  else
    M.render(bufnr)
    local s = (diff_states[bufnr] and diff_states[bufnr].stats) or {}
    vim.notify(
      string.format("SuperMarkdown Spec Diff: Active 󰄵 (+%d ~%d -%d changes)", s.added or 0, s.modified or 0, s.deleted or 0),
      vim.log.levels.INFO
    )
    return true
  end
end

--- Jump to next changed block
--- @param bufnr number
function M.jump_next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local hunks, _ = M.compute_diff(bufnr)
  if #hunks == 0 then
    vim.notify("SuperMarkdown: No changes detected against git HEAD", vim.log.levels.INFO)
    return
  end

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  for _, h in ipairs(hunks) do
    if h.start_line > cur_line then
      vim.api.nvim_win_set_cursor(0, { h.start_line, 0 })
      vim.cmd("normal! zvzz")
      return
    end
  end

  -- Wrap to first
  vim.api.nvim_win_set_cursor(0, { hunks[1].start_line, 0 })
  vim.cmd("normal! zvzz")
end

--- Jump to previous changed block
--- @param bufnr number
function M.jump_prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local hunks, _ = M.compute_diff(bufnr)
  if #hunks == 0 then
    vim.notify("SuperMarkdown: No changes detected against git HEAD", vim.log.levels.INFO)
    return
  end

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  for i = #hunks, 1, -1 do
    local h = hunks[i]
    if h.start_line < cur_line then
      vim.api.nvim_win_set_cursor(0, { h.start_line, 0 })
      vim.cmd("normal! zvzz")
      return
    end
  end

  -- Wrap to last
  local last = hunks[#hunks]
  vim.api.nvim_win_set_cursor(0, { last.start_line, 0 })
  vim.cmd("normal! zvzz")
end

--- Open Agent Change Eyeballer Dashboard
--- @param bufnr number
function M.open_diff_dashboard(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local hunks, stats = M.compute_diff(bufnr)
  local analysis = analyzer.analyze(bufnr)
  local sec_diffs = M.get_section_diffs(bufnr)

  if dash_win and vim.api.nvim_win_is_valid(dash_win) then
    pcall(vim.api.nvim_win_close, dash_win, true)
  end

  dash_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[dash_buf].bufhidden = "wipe"
  vim.bo[dash_buf].filetype = "supermarkdown_diff"

  local lines = {
    " 󰜥 SuperMarkdown: Agent Spec Changes & Eyeballer HUD",
    "──────────────────────────────────────────────────────────────────────────",
    string.format(" 󰈙 Document: %s", vim.fs.basename(analysis.filename or "SPEC.md")),
    string.format(" 󰮍 Changes vs HEAD: +%d Added  ·  ~%d Modified  ·  -%d Deleted", stats.added, stats.modified, stats.deleted),
    "──────────────────────────────────────────────────────────────────────────",
    "",
    " ## Sections Touched by Changes:",
  }

  local target_lines = {}
  local touched_count = 0
  for _, s in ipairs(analysis.sections or {}) do
    local sd = sec_diffs[s.lnum]
    if sd and (sd.added > 0 or sd.modified > 0 or sd.deleted > 0) then
      touched_count = touched_count + 1
      local item_line = #lines + 1
      target_lines[item_line] = s.lnum
      table.insert(lines, string.format("   ▶ %s%s  [+%d ~%d -%d] (Line %d)", string.rep("  ", s.level - 1), s.title, sd.added, sd.modified, sd.deleted, s.lnum))
    end
  end
  if touched_count == 0 then
    table.insert(lines, "   (No sections modified — spec is in sync with HEAD)")
  end

  table.insert(lines, "")
  table.insert(lines, " ## Detailed Change Hunks (press <CR> to eyeball line):")

  if #hunks == 0 then
    table.insert(lines, "   (Clean working tree — no unstaged or uncommitted changes)")
  else
    for idx, h in ipairs(hunks) do
      local type_icon = (h.type == "add") and "󰐕 Added" or ((h.type == "change") and "󰜥 Modified" or "󰍴 Deleted")
      local h_header = string.format("   [%d] %s at Line %d (new:%d, old:%d)", idx, type_icon, h.start_line, h.new_count, h.old_count)
      local item_line = #lines + 1
      target_lines[item_line] = h.start_line
      table.insert(lines, h_header)

      -- Show brief preview of added/modified lines
      for _, nl in ipairs(h.new_lines or {}) do
        if #lines < 200 then
          table.insert(lines, "       + " .. nl:sub(1, 70))
        end
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "──────────────────────────────────────────────────────────────────────────")
  table.insert(lines, " [q/Esc]: Close  ·  [<CR>]: Jump to Line  ·  [r]: Refresh Diff")

  vim.bo[dash_buf].modifiable = true
  vim.api.nvim_buf_set_lines(dash_buf, 0, -1, false, lines)
  vim.bo[dash_buf].modifiable = false

  local width = math.min(96, math.floor(vim.o.columns * 0.85))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  dash_win = vim.api.nvim_open_win(dash_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    title = " 󰜥 Spec Changes Eyeballer ",
    title_pos = "center",
  })

  -- Keybindings
  local opts = { buffer = dash_buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", function()
    if dash_win and vim.api.nvim_win_is_valid(dash_win) then
      vim.api.nvim_win_close(dash_win, true)
    end
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    if dash_win and vim.api.nvim_win_is_valid(dash_win) then
      vim.api.nvim_win_close(dash_win, true)
    end
  end, opts)
  vim.keymap.set("n", "r", function()
    M.open_diff_dashboard(bufnr)
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    local cursor_row = vim.api.nvim_win_get_cursor(dash_win)[1]
    local target_lnum = target_lines[cursor_row]
    if target_lnum then
      if dash_win and vim.api.nvim_win_is_valid(dash_win) then
        vim.api.nvim_win_close(dash_win, true)
      end
      vim.api.nvim_win_set_cursor(0, { target_lnum, 0 })
      vim.cmd("normal! zvzz")
    end
  end, opts)
end

return M
