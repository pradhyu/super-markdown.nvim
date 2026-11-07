local M = {}

local BULLET_ICONS = { "• ", "◦ ", "▪ ", "▫ " }

function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts or not opts.enabled then return end

  -- 1. Task Checkbox: ^(%s*)([%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$
  local indent, bullet_part, mark, _ = line:match("^(%s*)([%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$")
  if indent and bullet_part and mark then
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

    local start_col = #indent
    local end_col = #indent + #bullet_part + 3 -- conceal "- [x]" cleanly

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, start_col, {
      end_col = end_col,
      conceal = "",
      virt_text = {
        { icon_info.icon, icon_info.hl },
      },
      virt_text_pos = "inline",
      priority = 110,
    })

    if m == "-" and end_col < #line then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, end_col, {
        end_col = #line,
        hl_group = "SuperMarkdownCheckboxCanceled",
        priority = 95,
      })
    end
    return true
  end

  return false
end

return M
