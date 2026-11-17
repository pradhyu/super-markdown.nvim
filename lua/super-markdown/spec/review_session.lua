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
    status_hl = "SuperMarkdownReviewApproved"
  elseif sec.review_status == "REJECTED" then
    status_str = "󰀦 REVISION REQUESTED"
    status_hl = "SuperMarkdownReviewRejected"
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

  -- Rich tokenized syntax highlighting for the Review Cockpit HUD
  local ns_id = vim.api.nvim_create_namespace("super_markdown_cockpit_hl")
  vim.api.nvim_buf_clear_namespace(session_buf, ns_id, 0, -1)

  local function add_hl(line_idx, start_col, end_col, hl)
    pcall(vim.api.nvim_buf_add_highlight, session_buf, ns_id, hl, line_idx, start_col, end_col)
  end

  local function hl_pattern(line_idx, pattern, hl)
    local line_str = lines[line_idx + 1] or ""
    local s, e = line_str:find(pattern)
    while s do
      add_hl(line_idx, s - 1, e, hl)
      s, e = line_str:find(pattern, e + 1)
    end
  end

  -- Line 0: Title banner & status badge
  local line0 = lines[1]
  local title_prefix = string.format(" 󰡷 Spec Review Cockpit [%d/%d]", cur_sec_idx, #sections_cache)
  add_hl(0, 0, #title_prefix, "SuperMarkdownReviewTitle")
  local sep_s, sep_e = line0:find("—")
  if sep_s then
    add_hl(0, sep_s - 1, sep_e, "SuperMarkdownDivider")
    add_hl(0, sep_e + 1, -1, status_hl)
  end

  -- Line 1: Top divider
  add_hl(1, 0, -1, "SuperMarkdownDivider")

  -- Line 2: Section title & line target
  add_hl(2, 0, 9, "SuperMarkdownReviewLabel")
  local lnum_s, lnum_e = lines[3]:find("%(Line %d+%)")
  if lnum_s then
    add_hl(2, 10, lnum_s - 2, "SuperMarkdownReviewSectionTitle")
    add_hl(2, lnum_s - 1, lnum_e, "Comment")
  else
    add_hl(2, 10, -1, "SuperMarkdownReviewSectionTitle")
  end

  -- Line 3: Metrics, Tasks & Diff indicators
  add_hl(3, 0, 9, "SuperMarkdownReviewLabel")
  hl_pattern(3, "%d+/%d+%s+tasks", "SuperMarkdownCheckboxProgress")
  hl_pattern(3, "%d+%s+questions%s+%[%?%]", "SuperMarkdownCalloutQuestion")
  hl_pattern(3, "%d+%s+blockers%s+%[!%]", "SuperMarkdownCalloutCaution")
  hl_pattern(3, "󰌾%s+Security/DB%s+Hazards", "SuperMarkdownRiskHigh")
  hl_pattern(3, "•", "SuperMarkdownDivider")
  hl_pattern(3, "git:", "Comment")
  hl_pattern(3, "%+%d+", "SuperMarkdownReviewDiffAdd")
  hl_pattern(3, "~%d+", "SuperMarkdownReviewDiffMod")
  hl_pattern(3, "%-%d+", "SuperMarkdownReviewDiffDel")
  hl_pattern(3, "diff:%s+none", "Comment")

  -- Line 4: Findings
  add_hl(4, 0, 10, "SuperMarkdownReviewLabel")
  if #findings > 0 then
    if sec.has_hazards or (c.important and c.important > 0) then
      add_hl(4, 10, -1, "SuperMarkdownReviewHazard")
    else
      add_hl(4, 10, -1, "SuperMarkdownCalloutQuestion")
    end
  else
    add_hl(4, 10, -1, "SuperMarkdownReviewClean")
  end

  -- Line 5: Bottom divider
  add_hl(5, 0, -1, "SuperMarkdownDivider")

  -- Line 6: Keymap actions row 1
  hl_pattern(6, "%[a%]", "SuperMarkdownReviewKeyApprove")
  hl_pattern(6, "Approve", "SuperMarkdownReviewApproved")
  hl_pattern(6, "%[r%]", "SuperMarkdownReviewKeyReject")
  hl_pattern(6, "Request Changes", "SuperMarkdownReviewRejected")
  hl_pattern(6, "%[q%]", "SuperMarkdownReviewKeyQuestion")
  hl_pattern(6, "Ask Agent", "SuperMarkdownReviewQuestion")
  hl_pattern(6, "%[c%]", "SuperMarkdownReviewKeyComment")
  hl_pattern(6, "Comment", "SuperMarkdownCalloutInfo")
  hl_pattern(6, "%[x%]", "SuperMarkdownReviewKeyExport")
  hl_pattern(6, "Export", "SuperMarkdownSpecBadgeImpl")

  -- Line 7: Navigation keymaps row 2
  hl_pattern(7, "%[n/j%]", "SuperMarkdownReviewKeyNav")
  hl_pattern(7, "%[p/k%]", "SuperMarkdownReviewKeyNav")
  hl_pattern(7, "%[o%]", "SuperMarkdownReviewKeyNav")
  hl_pattern(7, "%[Esc%]", "Comment")
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
  pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:NormalFloat,FloatBorder:SuperMarkdownReviewTitle", { win = session_win })

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
