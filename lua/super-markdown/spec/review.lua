local analyzer = require("super-markdown.spec.analyzer")

local M = {}

--- Find current section or insert line beneath current heading
--- @param bufnr number
--- @param lnum? number
--- @return number target_lnum, string section_title
local function get_section_insert_pos(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cur_line = lnum
  if not cur_line then
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 and vim.api.nvim_win_is_valid(win) then
      cur_line = vim.api.nvim_win_get_cursor(win)[1]
    else
      cur_line = vim.api.nvim_win_get_cursor(0)[1]
    end
  end

  local sec = analyzer.get_section_at(bufnr, cur_line)
  if sec then
    return sec.lnum, sec.title
  end

  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for l = cur_line, 1, -1 do
    if all_lines[l] and all_lines[l]:match("^%s*#+%s") then
      return l, all_lines[l]:gsub("^%s*#+%s*", "")
    end
  end

  return 1, "Document"
end

--- Approve the active spec section with human review timestamp
--- @param bufnr? number
--- @param lnum? number
function M.review_approve(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr, lnum)
  local date_str = os.date("%Y-%m-%d %H:%M")
  local approve_badge = string.format("> [!APPROVED] Reviewed by human on %s", date_str)

  local next_line = vim.api.nvim_buf_get_lines(bufnr, head_lnum, head_lnum + 1, false)[1] or ""
  if next_line:match("^>%s*%[!APPROVED%]") or next_line:match("^>%s*%[!REJECTED%]") then
    -- Update existing badge
    vim.api.nvim_buf_set_lines(bufnr, head_lnum, head_lnum + 1, false, { approve_badge })
  else
    -- Insert new badge
    vim.api.nvim_buf_set_lines(bufnr, head_lnum, head_lnum, false, { "", approve_badge })
  end

  vim.notify(string.format("SuperMarkdown Review: Section '%s' marked APPROVED 󰄵", vim.trim(title)), vim.log.levels.INFO)
end

--- Add a human review question / directive for the AI agent
--- @param bufnr? number
--- @param question_text? string
--- @param lnum? number
function M.review_question(bufnr, question_text, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr, lnum)

  local function do_insert(text)
    if not text or vim.trim(text) == "" then return end
    local q_badge = string.format("> [!QUESTION] @agent: %s", vim.trim(text))
    local insert_lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, insert_lnum, insert_lnum, false, { "", q_badge })
    vim.notify(string.format("SuperMarkdown Review: Added directive for AI agent in '%s' 󰋽", vim.trim(title)), vim.log.levels.INFO)
  end

  if question_text and question_text ~= "" then
    do_insert(question_text)
  else
    vim.ui.input({ prompt = "Question / Directive for AI Agent: " }, function(input)
      if input then do_insert(input) end
    end)
  end
end

--- Add an inline human review comment
--- @param bufnr? number
--- @param comment_text? string
--- @param lnum? number
function M.review_comment(bufnr, comment_text, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr, lnum)

  local function do_insert(text)
    if not text or vim.trim(text) == "" then return end
    local date_str = os.date("%Y-%m-%d %H:%M")
    local r_badge = string.format("> [!REVIEW] @human (%s): %s", date_str, vim.trim(text))
    local insert_lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, insert_lnum, insert_lnum, false, { "", r_badge })
    vim.notify(string.format("SuperMarkdown Review: Added comment in '%s' 󰋽", vim.trim(title)), vim.log.levels.INFO)
  end

  if comment_text and comment_text ~= "" then
    do_insert(comment_text)
  else
    vim.ui.input({ prompt = "Human Review Comment / Note: " }, function(input)
      if input then do_insert(input) end
    end)
  end
end

--- Request revision / reject active section
--- @param bufnr? number
--- @param reason? string
--- @param lnum? number
function M.review_reject(bufnr, reason, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr, lnum)

  local function do_reject(text)
    local date_str = os.date("%Y-%m-%d %H:%M")
    local note = (text and text ~= "") and (" — " .. text) or ""
    local reject_badge = string.format("> [!REJECTED] Changes requested by human on %s%s", date_str, note)

    local next_line = vim.api.nvim_buf_get_lines(bufnr, head_lnum, head_lnum + 1, false)[1] or ""
    if next_line:match("^>%s*%[!APPROVED%]") or next_line:match("^>%s*%[!REJECTED%]") then
      vim.api.nvim_buf_set_lines(bufnr, head_lnum, head_lnum + 1, false, { reject_badge })
    else
      vim.api.nvim_buf_set_lines(bufnr, head_lnum, head_lnum, false, { "", reject_badge })
    end
    vim.notify(string.format("SuperMarkdown Review: Section '%s' marked REVISION REQUESTED 󰀦", vim.trim(title)), vim.log.levels.WARN)
  end

  if reason and reason ~= "" then
    do_reject(reason)
  else
    vim.ui.input({ prompt = "Reason for revision / rejection: " }, function(input)
      if input then do_reject(input) end
    end)
  end
end

--- Approve entire spec document
--- @param bufnr? number
function M.review_approve_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local date_str = os.date("%Y-%m-%d %H:%M")
  local user = vim.fn.getenv("USER") or "human"
  local updated = false

  -- Look for frontmatter or top metadata status
  for idx, l in ipairs(lines) do
    if idx <= 30 then
      if l:match("^%s*status%s*:%s*") then
        lines[idx] = string.format("status: APPROVED # reviewed by %s on %s", user, date_str)
        updated = true
        break
      elseif l:match("^>%s*%*%*[^%*]*[sS]tatus[^%*]*%*%*%s*:") then
        lines[idx] = string.format("> **Document Status**: `APPROVED` (Reviewed by %s on %s)", user, date_str)
        updated = true
        break
      end
    end
  end

  if not updated then
    -- Insert top blockquote status
    local insert_idx = 1
    for idx, l in ipairs(lines) do
      if l:match("^#%s+") then
        insert_idx = idx + 1
        break
      end
    end
    table.insert(lines, insert_idx, string.format("> **Document Status**: `APPROVED` (Reviewed by %s on %s)", user, date_str))
    table.insert(lines, insert_idx + 1, "")
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.notify(string.format("SuperMarkdown Review: Entire specification marked APPROVED by %s 󰄵", user), vim.log.levels.INFO)
end

--- Reject entire spec document with overarching reason
--- @param bufnr? number
--- @param reason? string
function M.review_reject_all(bufnr, reason)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local function do_reject_doc(text)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local date_str = os.date("%Y-%m-%d %H:%M")
    local user = vim.fn.getenv("USER") or "human"
    local note = (text and text ~= "") and (" — " .. text) or ""
    local updated = false

    for idx, l in ipairs(lines) do
      if idx <= 30 then
        if l:match("^%s*status%s*:%s*") then
          lines[idx] = string.format("status: REJECTED # %s requested changes on %s%s", user, date_str, note)
          updated = true
          break
        elseif l:match("^>%s*%*%*[^%*]*[sS]tatus[^%*]*%*%*%s*:") then
          lines[idx] = string.format("> **Document Status**: `REJECTED` (Changes requested by %s on %s%s)", user, date_str, note)
          updated = true
          break
        end
      end
    end

    if not updated then
      local insert_idx = 1
      for idx, l in ipairs(lines) do
        if l:match("^#%s+") then
          insert_idx = idx + 1
          break
        end
      end
      table.insert(lines, insert_idx, string.format("> **Document Status**: `REJECTED` (Changes requested by %s on %s%s)", user, date_str, note))
      table.insert(lines, insert_idx + 1, "")
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.notify("SuperMarkdown Review: Document marked REVISION REQUESTED 󰀦", vim.log.levels.WARN)
  end

  if reason and reason ~= "" then
    do_reject_doc(reason)
  else
    vim.ui.input({ prompt = "Overarching reason for spec rejection / revision: " }, function(input)
      if input then do_reject_doc(input) end
    end)
  end
end

--- Get review summary of the document
--- @param bufnr? number
--- @return table summary
function M.get_review_summary(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local analysis = analyzer.analyze(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local approved_sections = {}
  local rejected_sections = {}
  local open_questions = {}
  local human_comments = {}
  local blockers = {}

  for _, sec in ipairs(analysis.sections or {}) do
    if sec.review_status == "APPROVED" then
      table.insert(approved_sections, sec)
    elseif sec.review_status == "REJECTED" then
      table.insert(rejected_sections, sec)
    end
  end

  for _, item in ipairs(analysis.items or {}) do
    if item.kind == "question" then
      table.insert(open_questions, item)
    elseif item.kind == "blocker" then
      table.insert(blockers, item)
    elseif item.kind == "review" and not item.text:match("^%[APPROVED%]") and not item.text:match("^%[REJECTED%]") then
      table.insert(human_comments, item)
    end
  end

  return {
    bufnr = bufnr,
    analysis = analysis,
    approved_sections = approved_sections,
    rejected_sections = rejected_sections,
    open_questions = open_questions,
    human_comments = human_comments,
    blockers = blockers,
  }
end

--- Export comprehensive review feedback prompt for the AI agent
--- @param bufnr? number
--- @return string prompt_text
function M.review_export(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local summary = M.get_review_summary(bufnr)
  local analysis = summary.analysis
  local meta = analysis.metadata or {}
  local date_str = os.date("%Y-%m-%d %H:%M")
  local user = vim.fn.getenv("USER") or "human_reviewer"
  local filename = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))
  if filename == "" then filename = "SPEC.md" end

  local out = {}
  table.insert(out, "# Specification Review & Directives for AI Agent")
  table.insert(out, string.format("- **Target Specification**: `%s` (%s)", filename, meta.title or "Untitled Spec"))
  table.insert(out, string.format("- **Reviewer**: `%s`", user))
  table.insert(out, string.format("- **Timestamp**: %s", date_str))

  local verdict = "REVIEW COMPLETED"
  if #summary.rejected_sections > 0 or #summary.blockers > 0 then
    verdict = "REVISION REQUIRED (Changes Requested)"
  elseif #summary.approved_sections > 0 and #summary.rejected_sections == 0 and #summary.open_questions == 0 then
    verdict = "APPROVED (Ready for Implementation)"
  end
  table.insert(out, string.format("- **Review Verdict**: **%s**", verdict))
  table.insert(out, "")

  table.insert(out, "## 1. Review Summary Scorecard")
  table.insert(out, string.format("- **Sections Approved**: %d", #summary.approved_sections))
  table.insert(out, string.format("- **Sections Requiring Revision**: %d", #summary.rejected_sections))
  table.insert(out, string.format("- **Open Questions to Clarify**: %d", #summary.open_questions))
  table.insert(out, string.format("- **Critical Blockers to Resolve**: %d", #summary.blockers))
  table.insert(out, string.format("- **Human Review Notes**: %d", #summary.human_comments))
  table.insert(out, "")

  if #summary.rejected_sections > 0 then
    table.insert(out, "## 2. Sections Requiring Revision")
    for _, sec in ipairs(summary.rejected_sections) do
      table.insert(out, string.format("### %s (Line %d)", sec.title, sec.lnum))
      local reason = nil
      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, sec.lnum, math.min(sec.end_lnum, sec.lnum + 6), false)
      for _, bl in ipairs(buf_lines) do
        local r = bl:match("^>%s*%[!REJECTED%].-—%s*(.*)$")
        if r and r ~= "" then reason = r break end
      end
      if reason then
        table.insert(out, string.format("- **Revision Directives**: %s", reason))
      else
        table.insert(out, "- Human reviewer rejected this section. Please review the concerns and update the content.")
      end
    end
    table.insert(out, "")
  end

  if #summary.human_comments > 0 then
    table.insert(out, "## 3. Human Review Comments & Directives")
    for _, c in ipairs(summary.human_comments) do
      table.insert(out, string.format("- **[%s (L%d)]**: %s", c.section, c.lnum, c.text:gsub("^%[REVIEW NOTE%]%s*", "")))
    end
    table.insert(out, "")
  end

  if #summary.open_questions > 0 then
    table.insert(out, "## 4. Open Questions to Resolve")
    for _, q in ipairs(summary.open_questions) do
      table.insert(out, string.format("- **[%s (L%d)]**: %s", q.section, q.lnum, q.text))
    end
    table.insert(out, "")
  end

  if #summary.blockers > 0 then
    table.insert(out, "## 5. Critical Blockers to Resolve")
    for _, b in ipairs(summary.blockers) do
      table.insert(out, string.format("- **[%s (L%d)]**: %s", b.section, b.lnum, b.text))
    end
    table.insert(out, "")
  end

  if #summary.approved_sections > 0 then
    table.insert(out, "## 6. Approved Sections (Preserve Intact)")
    for _, sec in ipairs(summary.approved_sections) do
      table.insert(out, string.format("- `%s` (Line %d)", sec.title, sec.lnum))
    end
    table.insert(out, "")
  end

  table.insert(out, "## 7. Instructions for AI Agent")
  table.insert(out, "1. Address all revision requests, open questions, and blockers outlined above.")
  table.insert(out, "2. Keep all approved sections strictly intact unless direct dependencies require modification.")
  table.insert(out, "3. Provide concise, testable specifications and update the document status accordingly.")

  local prompt_text = table.concat(out, "\n")

  -- Copy to clipboard
  pcall(vim.fn.setreg, '"', prompt_text)
  pcall(vim.fn.setreg, "+", prompt_text)

  local ok_llm, llm_mod = pcall(require, "super-markdown.llm")
  if ok_llm and llm_mod.open_studio then
    llm_mod.open_studio({
      title = "AI Agent Spec Review Directives",
      system = "You are an expert software architect revising a specification based on human review directives.",
      prompt = prompt_text,
      target = filename,
      tokens = llm_mod.estimate_tokens(prompt_text),
      bufnr = bufnr,
    })
  end

  vim.notify(
    string.format("SuperMarkdown Review: Exported %d review items to clipboard & Prompt Studio 󰄵", #summary.rejected_sections + #summary.open_questions + #summary.human_comments + #summary.blockers),
    vim.log.levels.INFO
  )

  return prompt_text
end

M.export_prompt = M.review_export

return M
