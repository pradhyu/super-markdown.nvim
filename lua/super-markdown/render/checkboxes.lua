local M = {}

function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts.enabled then return end

  -- Match: ^(%s*[%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$
  local prefix, mark, rest = line:match("^(%s*[%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$")
  if not prefix then return end

  local icon_info = opts.icons.unchecked
  local m = mark:lower()

  if m == "x" then
    icon_info = opts.icons.checked
  elseif m == "-" then
    icon_info = opts.icons.canceled
  elseif m == "/" then
    icon_info = opts.icons.progress
  elseif m == "!" then
    icon_info = opts.icons.important
  elseif m == "?" then
    icon_info = opts.icons.question
  end

  local start_col = #prefix
  local end_col = start_col + 3 -- length of "[x]" is 3

  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, start_col, {
    end_col = end_col,
    conceal = "",
    virt_text = {
      { icon_info.icon, icon_info.hl },
    },
    virt_text_pos = "inline",
    priority = 110,
  })
end

return M
