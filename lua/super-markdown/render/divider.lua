local M = {}

function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts.enabled then return end

  -- Match horizontal rule: ^%s*([%-%*_])%s*%1%s*%1[%s%-%*_]*$
  if line:match("^%s*%-%s*%-%s*%-[%s%-]*$")
    or line:match("^%s*%*%s*%*%s*%*[%s%*]*$")
    or line:match("^%s*_%s*_%s*_[%s_]*$") then

    local hl = opts.hl or "SuperMarkdownDivider"
    local win = vim.fn.bufwinid(bufnr)
    local width = 70
    if win and win ~= -1 then
      width = math.max(40, vim.api.nvim_win_get_width(win) - 10)
    end

    local divider_line = string.rep(opts.char, width)

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
      end_col = #line,
      conceal = "",
      virt_text = {
        { divider_line, hl },
      },
      virt_text_pos = "overlay",
      priority = 100,
    })
  end
end

return M
