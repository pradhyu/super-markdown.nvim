local M = {}

--- Find all line numbers matching pattern in buffer
--- @param bufnr number
--- @param predicate fun(line: string): boolean
--- @return number[]
local function find_matching_lines(bufnr, predicate)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local matches = {}
  local in_fence = false

  for idx, l in ipairs(lines) do
    if l:match("^%s*```") or l:match("^%s*~~~") then
      in_fence = not in_fence
    end
    if predicate(l, in_fence) then
      table.insert(matches, idx)
    end
  end
  return matches
end

--- Jump to next or previous matching line
--- @param bufnr number
--- @param matches number[]
--- @param direction 1|-1
--- @param label string
local function jump(bufnr, matches, direction, label)
  if #matches == 0 then
    vim.notify("SuperMarkdown: No " .. label .. " found in document", vim.log.levels.INFO)
    return
  end

  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  if direction == 1 then
    for _, l in ipairs(matches) do
      if l > cur_line then
        vim.api.nvim_win_set_cursor(0, { l, 0 })
        vim.cmd("normal! zvzz")
        return
      end
    end
    -- Wrap to first
    vim.api.nvim_win_set_cursor(0, { matches[1], 0 })
    vim.cmd("normal! zvzz")
  else
    for i = #matches, 1, -1 do
      local l = matches[i]
      if l < cur_line then
        vim.api.nvim_win_set_cursor(0, { l, 0 })
        vim.cmd("normal! zvzz")
        return
      end
    end
    -- Wrap to last
    vim.api.nvim_win_set_cursor(0, { matches[#matches], 0 })
    vim.cmd("normal! zvzz")
  end
end

-- 1. Requirements (REQ-*, AC-*, ADR-*, RFC-*)
local function is_requirement(line)
  return line:match("%f[%a]REQ%-%d+") ~= nil
    or line:match("%f[%a]AC%-%d+") ~= nil
    or line:match("%f[%a]ADR%-%d+") ~= nil
    or line:match("%f[%a]RFC%-%d+") ~= nil
    or line:match("%f[%a]RULE%-%d+") ~= nil
end

function M.jump_next_requirement(bufnr)
  local m = find_matching_lines(bufnr, is_requirement)
  jump(bufnr, m, 1, "requirements (REQ-*/AC-*)")
end

function M.jump_prev_requirement(bufnr)
  local m = find_matching_lines(bufnr, is_requirement)
  jump(bufnr, m, -1, "requirements (REQ-*/AC-*)")
end

-- 2. Open Questions ([?] or > [!QUESTION])
local function is_question(line)
  return line:match("^%s*[%-%*%+]%s+%[%?%]") ~= nil
    or line:match("^%s*%d+%.%s+%[%?%]") ~= nil
    or line:match("^%s*>%s*%[!QUESTION%]") ~= nil
end

function M.jump_next_question(bufnr)
  local m = find_matching_lines(bufnr, is_question)
  jump(bufnr, m, 1, "open questions ([?])")
end

function M.jump_prev_question(bufnr)
  local m = find_matching_lines(bufnr, is_question)
  jump(bufnr, m, -1, "open questions ([?])")
end

-- 3. Blockers ([!] or > [!CAUTION] / > [!DANGER])
local function is_blocker(line)
  return line:match("^%s*[%-%*%+]%s+%[%!%]") ~= nil
    or line:match("^%s*%d+%.%s+%[%!%]") ~= nil
    or line:match("^%s*>%s*%[!CAUTION%]") ~= nil
    or line:match("^%s*>%s*%[!DANGER%]") ~= nil
end

function M.jump_next_blocker(bufnr)
  local m = find_matching_lines(bufnr, is_blocker)
  jump(bufnr, m, 1, "blockers ([!])")
end

function M.jump_prev_blocker(bufnr)
  local m = find_matching_lines(bufnr, is_blocker)
  jump(bufnr, m, -1, "blockers ([!])")
end

-- 4. Pending Tasks ([ ] or [/])
local function is_pending_task(line)
  return line:match("^%s*[%-%*%+]%s+%[[%s%/]%]") ~= nil
    or line:match("^%s*%d+%.%s+%[[%s%/]%]") ~= nil
end

function M.jump_next_task(bufnr)
  local m = find_matching_lines(bufnr, is_pending_task)
  jump(bufnr, m, 1, "pending tasks ([ ])")
end

function M.jump_prev_task(bufnr)
  local m = find_matching_lines(bufnr, is_pending_task)
  jump(bufnr, m, -1, "pending tasks ([ ])")
end

-- 5. Changes (using diff module)
function M.jump_next_change(bufnr)
  require("super-markdown.spec.diff").jump_next(bufnr)
end

function M.jump_prev_change(bufnr)
  require("super-markdown.spec.diff").jump_prev(bufnr)
end

return M
