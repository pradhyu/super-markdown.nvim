local config = require("super-markdown.config")

local M = {}

function M.get_headings(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local headings = {}
  local icons = config.options.render.headings.icons or { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " }

  local in_codeblock = false

  for lnum, line in ipairs(lines) do
    if line:match("^%s*```") then
      in_codeblock = not in_codeblock
    elseif not in_codeblock then
      local hashes, title = line:match("^(#+)%s+(.*)$")
      if hashes and #hashes <= 6 and title then
        local level = #hashes
        local icon = icons[level] or "󰲡 "
        local indent = string.rep("  ", level - 1)
        local display = string.format("%s%s%s", indent, icon, vim.trim(title))

        table.insert(headings, {
          lnum = lnum,
          level = level,
          title = vim.trim(title),
          icon = icon,
          display = display,
          bufnr = bufnr,
          line = line,
        })
      end
    end
  end

  return headings
end

return M
