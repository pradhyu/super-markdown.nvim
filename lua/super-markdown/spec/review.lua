local analyzer = require("super-markdown.spec.analyzer")

local M = {}

--- Find current section or insert line beneath current heading
--- @param bufnr number
--- @return number target_lnum, string section_title
local function get_section_insert_pos(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local sec = analyzer.get_section_at(bufnr, cur_line)

  if sec then
    return sec.lnum, sec.title
  end

  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for l = cur_line, 1, -1 do
    if all_lines[l]:match("^%s*#+%s") then
      return l, all_lines[l]:gsub("^%s*#+%s*", "")
    end
  end

  return 1, "Document"
end

--- Approve the active spec section with human review timestamp
--- @param bufnr? number
function M.review_approve(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr)
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
function M.review_question(bufnr, question_text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr)

  local function do_insert(text)
    if not text or vim.trim(text) == "" then return end
    local q_badge = string.format("> [!QUESTION] @agent: %s", vim.trim(text))
    local cur_cursor = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, cur_cursor, cur_cursor, false, { "", q_badge })
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

--- Request revision / reject active section
--- @param bufnr? number
--- @param reason? string
function M.review_reject(bufnr, reason)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local head_lnum, title = get_section_insert_pos(bufnr)

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

return M
