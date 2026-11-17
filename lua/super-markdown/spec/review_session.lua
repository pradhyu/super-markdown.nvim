local analyzer = require("super-markdown.spec.analyzer")
local review = require("super-markdown.spec.review")
local diff_mod = require("super-markdown.spec.diff")

local M = {}

local session_win = nil
local session_buf = nil
local source_buf = nil
local source_win = nil
local cur_sec_idx = 1
local sections_cache = {}

local function render_cockpit()
  if not session_win or not vim.api.nvim_win_is_valid(session_win) then return end
  if not session_buf or not vim.api.nvim_buf_is_valid(session_buf) then return end
  if #sections_cache == 0 then return end

  cur_sec_idx = math.max(1, math.min(#sections_cache, cur_sec_idx))
  local sec = sections_cache[cur_sec_idx]

  -- Refresh diff stats for this section
  local diff_str = "diff: none"
  local ok_df, sec_diffs = pcall(diff_mod.get_section_diffs, source_buf)
  if ok_df and sec_diffs and sec_diffs[sec.lnum] then
    local sd = sec_diffs[sec.lnum]
    if sd.added > 0 or sd.modified > 0 or sd.deleted > 0 then
      diff_str = string.format("git: +%d ~%d -%d", sd.added, sd.modified, sd.deleted)
    end
  end

  local status_str = "[PENDING REVIEW]"
  local status_hl = "SuperMarkdownMermaidWait"
  if sec.review_status == "APPROVED" then
    status_str = "󰄵 APPROVED"
    status_hl = "SuperMarkdownCheckboxChecked"
  elseif sec.review_status == "REJECTED" then
    status_str = "󰀦 REVISION REQUESTED"
    status_hl = "SuperMarkdownCalloutCaution"
  end

  local c = sec.counts or {}
  local task_str = string.format("%d/%d tasks", c.checked or 0, c.total_tasks or 0)
  local q_str = (c.question and c.question > 0) and string.format(" • %d questions [?]", c.question) or ""
  local b_str = (c.important and c.important > 0) and string.format(" • %d blockers [!]", c.important) or ""
  local h_str = (sec.has_hazards) and " • 󰌾 Security/DB Hazards" or ""

  local title_truncated = sec.title
  if #title_truncated > 50 then
    title_truncated = title_truncated:sub(1, 47) .. "..."
  end

  local lines = {
    string.format(" 󰡷 Spec Review Cockpit [%d/%d] — %s", cur_sec_idx, #sections_cache, status_str),
    "─────────────────────────────────────────────────────────────────────────────",
    string.format(" Section: %s (Line %d)", title_truncated, sec.lnum),
    string.format(" Metrics: %s%s%s%s • %s", task_str, q_str, b_str, h_str, diff_str),
  }

  -- Key findings in this section
  local findings = {}
  if sec.has_hazards then
    table.insert(findings, "Critical security, database migration, or destructive operation in section")
  end
  if c.question and c.question > 0 then
    table.insert(findings, string.format("%d unanswered question(s) needing clarification from author/agent", c.question))
  end
  if c.important and c.important > 0 then
    table.insert(findings, string.format("%d high-priority blocker(s) flagged", c.important))
  end

  if #findings > 0 then
    table.insert(lines, " Findings: " .. table.concat(findings, " | "))
  else
    table.insert(lines, " Findings: Clean section structure, ready for sign-off")
  end

  table.insert(lines, "─────────────────────────────────────────────────────────────────────────────")
  table.insert(lines, " [a] Approve   [r] Request Changes   [q] Ask Agent   [c] Comment   [x] Export")
  table.insert(lines, " [n/j] Next    [p/k] Previous        [o] Focus Source              [Esc] Close")

  vim.bo[session_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session_buf, 0, -1, false, lines)
  vim.bo[session_buf].modifiable = false

  -- Jump source window to section heading
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    pcall(vim.api.nvim_win_set_cursor, source_win, { sec.lnum, 0 })
    pcall(vim.api.nvim_win_call, source_win, function()
      vim.cmd("normal! zvzz")
    end)
  end

  pcall(vim.api.nvim_buf_add_highlight, session_buf, -1, status_hl, 0, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, session_buf, -1, "SuperMarkdownDivider", 1, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, session_buf, -1, "SuperMarkdownDivider", 5, 0, -1)
end

local function reload_sections()
  local analysis = analyzer.analyze(source_buf)
  sections_cache = analysis.sections or {}
end

--- Start or resume interactive Spec Review Session
--- @param bufnr? number
function M.start(bufnr)
  source_buf = bufnr or vim.api.nvim_get_current_buf()
  source_win = vim.api.nvim_get_current_win()

  reload_sections()
  if #sections_cache == 0 then
    vim.notify("SuperMarkdown Review: No structured headings found in document", vim.log.levels.WARN)
    return
  end

  -- Determine initial section matching cursor line
  local cur_line = vim.api.nvim_win_get_cursor(source_win)[1]
  cur_sec_idx = 1
  for i, s in ipairs(sections_cache) do
    if s.lnum <= cur_line then
      cur_sec_idx = i
    else
      break
    end
  end

  if session_win and vim.api.nvim_win_is_valid(session_win) then
    vim.api.nvim_win_close(session_win, true)
    session_win = nil
    session_buf = nil
  end

  session_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[session_buf].buftype = "nofile"
  vim.bo[session_buf].bufhidden = "wipe"
  vim.bo[session_buf].filetype = "supermarkdown_cockpit"

  local width = math.min(84, vim.o.columns - 4)
  local height = 8
  local row = vim.o.lines - height - 3
  local col = math.floor((vim.o.columns - width) / 2)

  session_win = vim.api.nvim_open_win(session_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " 󰡷 Human Spec Review Cockpit ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_option_value, "cursorline", false, { win = session_win })

  local function close_session()
    if session_win and vim.api.nvim_win_is_valid(session_win) then
      vim.api.nvim_win_close(session_win, true)
    end
    session_win = nil
    session_buf = nil
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_set_current_win, source_win)
    end
  end

  local function next_sec()
    if cur_sec_idx < #sections_cache then
      cur_sec_idx = cur_sec_idx + 1
      render_cockpit()
    end
  end

  local function prev_sec()
    if cur_sec_idx > 1 then
      cur_sec_idx = cur_sec_idx - 1
      render_cockpit()
    end
  end

  local function approve_current()
    M.approve()
    if cur_sec_idx < #sections_cache then
      cur_sec_idx = cur_sec_idx + 1
      render_cockpit()
    end
  end

  local function reject_current()
    M.reject()
  end

  local function ask_agent()
    local sec = sections_cache[cur_sec_idx]
    if sec and source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_set_cursor(source_win, { sec.lnum, 0 })
      vim.ui.input({ prompt = "Question / Directive for AI Agent: " }, function(input)
        if input and input ~= "" then
          review.review_question(source_buf, input)
          reload_sections()
          render_cockpit()
        end
      end)
    end
  end

  local function add_comment()
    local sec = sections_cache[cur_sec_idx]
    if sec and source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_set_cursor(source_win, { sec.lnum, 0 })
      vim.ui.input({ prompt = "Human Review Comment / Note: " }, function(input)
        if input and input ~= "" then
          review.review_comment(source_buf, input)
          reload_sections()
          render_cockpit()
        end
      end)
    end
  end

  local function export_bundle()
    review.export_prompt(source_buf)
  end

  local function focus_source()
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    end
  end

  local bopts = { buffer = session_buf, nowait = true, silent = true, noremap = true }
  vim.keymap.set("n", "q", close_session, bopts)
  vim.keymap.set("n", "<Esc>", close_session, bopts)
  vim.keymap.set("n", "n", next_sec, bopts)
  vim.keymap.set("n", "j", next_sec, bopts)
  vim.keymap.set("n", "p", prev_sec, bopts)
  vim.keymap.set("n", "k", prev_sec, bopts)
  vim.keymap.set("n", "a", approve_current, bopts)
  vim.keymap.set("n", "r", reject_current, bopts)
  vim.keymap.set("n", "c", add_comment, bopts)
  vim.keymap.set("n", "x", export_bundle, bopts)
  vim.keymap.set("n", "e", export_bundle, bopts)
  vim.keymap.set("n", "o", focus_source, bopts)

  render_cockpit()
end

--- Get the currently inspected section in the review session
function M.get_current_section()
  if #sections_cache == 0 then return nil end
  return sections_cache[cur_sec_idx]
end

--- Advance to next section in the review session
function M.next()
  if cur_sec_idx < #sections_cache then
    cur_sec_idx = cur_sec_idx + 1
    render_cockpit()
  end
end

--- Go to previous section in the review session
function M.prev()
  if cur_sec_idx > 1 then
    cur_sec_idx = cur_sec_idx - 1
    render_cockpit()
  end
end

--- Approve current section
function M.approve()
  local sec = sections_cache[cur_sec_idx]
  if sec then
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_set_cursor(source_win, { sec.lnum, 0 })
    end
    review.review_approve(source_buf, sec.lnum)
    reload_sections()
    render_cockpit()
  end
end

--- Reject current section with optional reason
--- @param reason? string
function M.reject(reason)
  local sec = sections_cache[cur_sec_idx]
  if not sec then return end
  if reason then
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_set_cursor(source_win, { sec.lnum, 0 })
    end
    review.review_reject(source_buf, reason, sec.lnum)
    reload_sections()
    render_cockpit()
  else
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_win_set_cursor(source_win, { sec.lnum, 0 })
      vim.ui.input({ prompt = string.format("Reason for revision in '%s': ", sec.title) }, function(input)
        if input and input ~= "" then
          review.review_reject(source_buf, input, sec.lnum)
          reload_sections()
          if cur_sec_idx < #sections_cache then
            cur_sec_idx = cur_sec_idx + 1
          end
          render_cockpit()
        end
      end)
    end
  end
end

--- Check if review session is currently active
function M.is_open()
  return session_win ~= nil and vim.api.nvim_win_is_valid(session_win)
end

--- Close review session
function M.close()
  if session_win and vim.api.nvim_win_is_valid(session_win) then
    vim.api.nvim_win_close(session_win, true)
  end
  session_win = nil
  session_buf = nil
  return true
end

return M
