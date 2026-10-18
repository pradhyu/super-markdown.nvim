local M = {}

function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts.enabled then return end

  -- Match heading: ^(#+)%s+(.*)$
  local hashes, title = line:match("^(#+)%s+(.*)$")
  if not hashes or #hashes > 6 then return end

  local level = #hashes
  local icon = opts.icons[level] or "󰲡 "
  local fg_hl = opts.foregrounds[level] or "SuperMarkdownH1"
  local bg_hl = opts.backgrounds[level] or "SuperMarkdownH1Bg"

  -- Replace the leading hashes and space with icon and styled text
  -- We use extmarks with virt_text_win_col or inline conceal
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
    end_col = #hashes + 1,
    conceal = "",
    virt_text = {
      { icon, fg_hl },
    },
    virt_text_pos = "inline",
    line_hl_group = level <= 2 and bg_hl or nil,
    priority = 100,
  })
end

return M
