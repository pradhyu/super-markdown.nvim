local M = {}

local cycle_order = {
  [" "] = "x",
  ["x"] = "-",
  ["-"] = "/",
  ["/"] = " ",
  ["X"] = "-",
}

function M.toggle(cycle)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

  if not line then return end

  -- Match: ^(%s*[%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$
  local prefix, mark, rest = line:match("^(%s*[%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$")
  if prefix and mark then
    local new_mark = "x"
    if cycle then
      new_mark = cycle_order[mark] or " "
    else
      -- Simple toggle
      if mark:lower() == "x" then
        new_mark = " "
      else
        new_mark = "x"
      end
    end

    local new_line = string.format("%s[%s]%s", prefix, new_mark, rest)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
  else
    -- If line does not have a checkbox, turn bullet into checkbox
    local b_prefix, b_rest = line:match("^(%s*[%-%*%+]%s+)(.*)$")
    if b_prefix then
      local new_line = string.format("%s[ ] %s", b_prefix, b_rest)
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
    end
  end
end

return M
