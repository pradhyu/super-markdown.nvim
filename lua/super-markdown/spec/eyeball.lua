local analyzer = require("super-markdown.spec.analyzer")
local review_mod = require("super-markdown.spec.review")

local M = {}

local hud_win = nil
local hud_buf = nil
local NS_EYEBALL = vim.api.nvim_create_namespace("super_markdown_eyeball_hud")

--- Render a visual progress bar string
--- @param done number
--- @param total number
--- @param width number
--- @return string
local function make_progress_bar(done, total, width)
  width = width or 20
  if total <= 0 then
    return string.rep("░", width) .. " 100% (0/0 tasks)"
  end
  local ratio = math.max(0, math.min(1, done / total))
  local filled = math.floor(ratio * width + 0.5)
  local empty = width - filled
  local pct = math.floor(ratio * 100 + 0.5)
  return string.format("%s%s %d%% (%d/%d tasks)", string.rep("█", filled), string.rep("░", empty), pct, done, total)
end

--- Close Eyeball HUD if open
function M.close()
  if hud_win and vim.api.nvim_win_is_valid(hud_win) then
    pcall(vim.api.nvim_win_close, hud_win, true)
  end
  hud_win = nil
  hud_buf = nil
end

--- Check if HUD is open
--- @return boolean
function M.is_open()
  return hud_win ~= nil and vim.api.nvim_win_is_valid(hud_win)
end

--- Open or toggle the interactive Agent Spec Eyeballer & Scorecard HUD
--- @param bufnr? number
function M.open(bufnr)
  if M.is_open() then
    M.close()
    return
  end

  local source_buf = bufnr or vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local analysis = analyzer.analyze(source_buf)
  local lines_raw = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)

  -- Calculate reading statistics
  local word_count = 0
  for _, l in ipairs(lines_raw) do
    for _ in l:gmatch("%S+") do
      word_count = word_count + 1
    end
  end
  local full_read_min = math.max(1, math.ceil(word_count / 200))
  local skim_sec = math.max(10, math.ceil(word_count / 30))

  local meta = analysis.metadata or {}
  local t = analysis.totals or {}

  local lines = {}
  local line_targets = {} -- HUD line index (1-based) -> source line number
  local line_sections = {} -- HUD line index -> section object

  local function add_line(text, target_lnum, sec)
    table.insert(lines, text)
    if target_lnum then
      line_targets[#lines] = target_lnum
    end
    if sec then
      line_sections[#lines] = sec
    end
  end

  add_line(" 󰍔 SuperMarkdown: Agent Spec Eyeballer & Scorecard HUD")
  add_line(" " .. string.rep("─", 74))

  local doc_title = meta.title or vim.fs.basename(vim.api.nvim_buf_get_name(source_buf))
  local status_str = meta.status or "DRAFT"
  local ver_str = meta.version and ("v" .. meta.version) or "unversioned"

  add_line(string.format("   Spec: %s", doc_title), 1)
  add_line(string.format("   Status: [%s]   Version: %s   Readiness: %d/100", status_str, ver_str, analysis.readiness or 100), meta.status_lnum or 1)
  add_line(string.format("   Length: %d lines · ~%d words · Full Read: ~%d min · Skim: ~%ds", #lines_raw, word_count, full_read_min, skim_sec))
  add_line(string.format("   Progress: %s", make_progress_bar(t.checked or 0, t.total_tasks or 0, 22)))
  add_line(string.format(
    "   Radar:  󰄵 %d Done  │  󰄱 %d Todo  │  󰀦 %d Blockers  │  󰳦 %d Risks  │  󰋽 %d Questions  │  󰚩 %d Fluff",
    t.checked or 0, t.unchecked or 0, t.important or 0, t.risks or 0, t.question or 0, t.fluff or 0
  ))
  add_line(" " .. string.rep("─", 74))
  add_line(" ## Section Review Matrix (press <CR> to jump, 'a' approve, 'r' reject, 'q' question):")
  add_line("")

  for _, sec in ipairs(analysis.sections or {}) do
    local indent = string.rep("  ", math.max(0, sec.level - 1))
    local st_badge = "[󰄱 UNREVIEWED]"
    if sec.review_status == "APPROVED" then
      st_badge = "[󰄵 APPROVED  ]"
    elseif sec.review_status == "REJECTED" then
      st_badge = "[󰀦 REVISION  ]"
    elseif sec.counts and sec.counts.question and sec.counts.question > 0 then
      st_badge = "[󰋽 QUESTION  ]"
    end

    local extras = {}
    if sec.counts then
      if sec.counts.total_tasks and sec.counts.total_tasks > 0 then
        table.insert(extras, string.format("󰄵 %d/%d", sec.counts.checked or 0, sec.counts.total_tasks))
      end
      if sec.counts.risks and sec.counts.risks > 0 then
        table.insert(extras, string.format("󰳦 %d risk%s", sec.counts.risks, sec.counts.risks > 1 and "s" or ""))
      end
      if sec.counts.question and sec.counts.question > 0 then
        table.insert(extras, string.format("󰋽 %d Q", sec.counts.question))
      end
      if sec.counts.scenarios and sec.counts.scenarios > 0 then
        table.insert(extras, string.format("󰄵 %d AC", sec.counts.scenarios))
      end
    end
    local extra_str = #extras > 0 and ("  (" .. table.concat(extras, " · ") .. ")") or ""

    local row_str = string.format("   %s %s%s %s (L%d)", st_badge, indent, sec.title, extra_str, sec.lnum)
    add_line(row_str, sec.lnum, sec)
  end

  add_line("")
  add_line(" " .. string.rep("─", 74))
  add_line(" [<CR>]: Jump · [a]: Approve · [r]: Reject · [?]: Question · [s]: Skim · [e]: Export · [q/Esc]: Close")

  hud_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[hud_buf].bufhidden = "wipe"
  vim.bo[hud_buf].filetype = "supermarkdown_eyeball"

  vim.bo[hud_buf].modifiable = true
  vim.api.nvim_buf_set_lines(hud_buf, 0, -1, false, lines)
  vim.bo[hud_buf].modifiable = false

  local width = math.min(92, math.floor(vim.o.columns * 0.88))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.82))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  hud_win = vim.api.nvim_open_win(hud_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    title = " 󰍔 Agent Spec Eyeballer & Scorecard ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = hud_win })
  pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:NormalFloat,FloatBorder:SuperMarkdownReviewTitle", { win = hud_win })

  local function add_hl(line_idx, start_col, end_col, hl)
    pcall(vim.api.nvim_buf_add_highlight, hud_buf, NS_EYEBALL, hl, line_idx, start_col, end_col)
  end

  local function hl_pattern(line_idx, pattern, hl)
    local line_str = lines[line_idx + 1] or ""
    local s, e = line_str:find(pattern)
    while s do
      add_hl(line_idx, s - 1, e, hl)
      s, e = line_str:find(pattern, e + 1)
    end
  end

  -- Apply syntax highlights inside HUD
  add_hl(0, 0, -1, "SuperMarkdownReviewTitle")
  add_hl(1, 0, -1, "SuperMarkdownDivider")

  -- Labels on top metadata
  add_hl(2, 0, 8, "SuperMarkdownReviewLabel")
  add_hl(3, 0, 10, "SuperMarkdownReviewLabel")
  add_hl(4, 0, 10, "SuperMarkdownReviewLabel")
  add_hl(5, 0, 12, "SuperMarkdownReviewLabel")
  add_hl(6, 0, 10, "SuperMarkdownReviewLabel")

  -- Status & Readiness
  hl_pattern(3, "%[%a+[^%]]*%]", "SuperMarkdownSpecReqId")
  hl_pattern(3, "Readiness:%s+%d+/100", "SuperMarkdownReviewApproved")

  -- Progress bar
  hl_pattern(5, "Progress:%s+.*", "SuperMarkdownReviewApproved")

  -- Radar icons & counts
  hl_pattern(6, "󰄵%s+%d+%s+Done", "SuperMarkdownReviewApproved")
  hl_pattern(6, "󰄱%s+%d+%s+Todo", "Comment")
  hl_pattern(6, "󰀦%s+%d+%s+Blockers", "SuperMarkdownCalloutCaution")
  hl_pattern(6, "󰳦%s+%d+%s+Risks", "SuperMarkdownRiskHigh")
  hl_pattern(6, "󰋽%s+%d+%s+Questions", "SuperMarkdownCalloutQuestion")
  hl_pattern(6, "󰚩%s+%d+%s+Fluff", "SuperMarkdownSpecBadgeImpl")
  hl_pattern(6, "│", "SuperMarkdownDivider")

  add_hl(7, 0, -1, "SuperMarkdownDivider")

  for idx, l in ipairs(lines) do
    local lnum = idx - 1
    if l:match("^%s*## Section Review Matrix") then
      add_hl(lnum, 0, -1, "SuperMarkdownH2")
    elseif l:match("%[󰄵 APPROVED") then
      pcall(vim.api.nvim_buf_set_extmark, hud_buf, NS_EYEBALL, lnum, 3, {
        end_col = 19,
        hl_group = "SuperMarkdownReviewApproved",
        priority = 90,
      })
      hl_pattern(lnum, "%(L%d+%)", "Comment")
      hl_pattern(lnum, "%([^%)]+%)", "SuperMarkdownInlineCode")
    elseif l:match("%[󰀦 REVISION") then
      pcall(vim.api.nvim_buf_set_extmark, hud_buf, NS_EYEBALL, lnum, 3, {
        end_col = 19,
        hl_group = "SuperMarkdownReviewRejected",
        priority = 90,
      })
      hl_pattern(lnum, "%(L%d+%)", "Comment")
      hl_pattern(lnum, "%([^%)]+%)", "SuperMarkdownInlineCode")
    elseif l:match("%[󰋽 QUESTION") then
      pcall(vim.api.nvim_buf_set_extmark, hud_buf, NS_EYEBALL, lnum, 3, {
        end_col = 19,
        hl_group = "SuperMarkdownCheckboxQuestion",
        priority = 90,
      })
      hl_pattern(lnum, "%(L%d+%)", "Comment")
      hl_pattern(lnum, "%([^%)]+%)", "SuperMarkdownInlineCode")
    elseif l:match("%[󰄱 UNREVIEWED") then
      pcall(vim.api.nvim_buf_set_extmark, hud_buf, NS_EYEBALL, lnum, 3, {
        end_col = 19,
        hl_group = "Comment",
        priority = 90,
      })
      hl_pattern(lnum, "%(L%d+%)", "Comment")
      hl_pattern(lnum, "%([^%)]+%)", "SuperMarkdownInlineCode")
    end
  end

  -- Bottom divider and footer
  add_hl(#lines - 2, 0, -1, "SuperMarkdownDivider")
  hl_pattern(#lines - 1, "%[<CR>%]", "SuperMarkdownReviewKeyNav")
  hl_pattern(#lines - 1, "%[a%]", "SuperMarkdownReviewKeyApprove")
  hl_pattern(#lines - 1, "%[r%]", "SuperMarkdownReviewKeyReject")
  hl_pattern(#lines - 1, "%[%?%]", "SuperMarkdownReviewKeyQuestion")
  hl_pattern(#lines - 1, "%[s%]", "SuperMarkdownReviewKeyNav")
  hl_pattern(#lines - 1, "%[e%]", "SuperMarkdownReviewKeyExport")
  hl_pattern(#lines - 1, "%[q/Esc%]", "Comment")

  -- Keybindings inside HUD
  local bopts = { buffer = hud_buf, silent = true, nowait = true }

  local function close_self()
    M.close()
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      pcall(vim.api.nvim_set_current_win, source_win)
    end
  end

  vim.keymap.set("n", "q", close_self, bopts)
  vim.keymap.set("n", "<Esc>", close_self, bopts)

  -- Jump to section
  vim.keymap.set("n", "<CR>", function()
    local cursor_row = vim.api.nvim_win_get_cursor(hud_win)[1]
    local target = line_targets[cursor_row]
    close_self()
    if target and target > 0 then
      pcall(vim.api.nvim_win_set_cursor, 0, { target, 0 })
      vim.cmd("normal! zvzz")
    end
  end, bopts)

  -- Approve section
  vim.keymap.set("n", "a", function()
    local cursor_row = vim.api.nvim_win_get_cursor(hud_win)[1]
    local sec = line_sections[cursor_row]
    if sec and sec.lnum then
      pcall(vim.api.nvim_win_set_cursor, source_win, { sec.lnum, 0 })
      review_mod.review_approve(source_buf)
      M.close()
      M.open(source_buf)
    else
      vim.notify("SuperMarkdown: Move cursor to a section line to approve", vim.log.levels.INFO)
    end
  end, bopts)

  -- Reject section
  vim.keymap.set("n", "r", function()
    local cursor_row = vim.api.nvim_win_get_cursor(hud_win)[1]
    local sec = line_sections[cursor_row]
    if sec and sec.lnum then
      pcall(vim.api.nvim_win_set_cursor, source_win, { sec.lnum, 0 })
      M.close()
      review_mod.review_reject(source_buf)
    else
      vim.notify("SuperMarkdown: Move cursor to a section line to request revision", vim.log.levels.INFO)
    end
  end, bopts)

  -- Add question (? or Q)
  local function add_question()
    local cursor_row = vim.api.nvim_win_get_cursor(hud_win)[1]
    local sec = line_sections[cursor_row]
    if sec and sec.lnum then
      pcall(vim.api.nvim_win_set_cursor, source_win, { sec.lnum, 0 })
      M.close()
      review_mod.review_question(source_buf)
    else
      vim.notify("SuperMarkdown: Move cursor to a section line to add directive", vim.log.levels.INFO)
    end
  end
  vim.keymap.set("n", "?", add_question, bopts)
  vim.keymap.set("n", "Q", add_question, bopts)

  -- Toggle Skim Mode
  vim.keymap.set("n", "s", function()
    require("super-markdown.skim").toggle(source_buf)
    close_self()
  end, bopts)

  -- Export review directives
  vim.keymap.set("n", "e", function()
    close_self()
    review_mod.review_export(source_buf)
  end, bopts)

  -- Refresh
  vim.keymap.set("n", "R", function()
    M.close()
    M.open(source_buf)
  end, bopts)
end

return M
