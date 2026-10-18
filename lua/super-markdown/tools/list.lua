local M = {}

function M.handle_enter()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  -- 1. Check for empty bullet: e.g. "^%s*[%-%*%+]%s*$"
  local empty_unordered = line:match("^(%s*)[%-%*%+]%s*$")
  if empty_unordered then
    -- Remove the bullet and leave empty line
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { "" })
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    return true
  end

  -- 2. Check for empty numbered list: e.g. "^%s*%d+%.%s*$"
  local empty_ordered = line:match("^(%s*)%d+%.%s*$")
  if empty_ordered then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { "" })
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    return true
  end

  -- 3. Match active unordered list: ^(%s*[%-%*%+]%s+)
  local u_indent, u_bullet = line:match("^(%s*)([%-%*%+])%s+")
  if u_indent and u_bullet then
    local new_prefix = u_indent .. u_bullet .. " "
    -- Insert newline with prefix
    local current_text = line:sub(1, col)
    local next_text = line:sub(col + 1)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { current_text, new_prefix .. next_text })
    vim.api.nvim_win_set_cursor(0, { lnum + 1, #new_prefix })
    return true
  end

  -- 4. Match active ordered list: ^(%s*)(%d+)%.%s+
  local o_indent, o_num = line:match("^(%s*)(%d+)%.%s+")
  if o_indent and o_num then
    local next_num = tonumber(o_num) + 1
    local new_prefix = string.format("%s%d. ", o_indent, next_num)
    local current_text = line:sub(1, col)
    local next_text = line:sub(col + 1)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { current_text, new_prefix .. next_text })
    vim.api.nvim_win_set_cursor(0, { lnum + 1, #new_prefix })
    return true
  end

  return false
end

return M
