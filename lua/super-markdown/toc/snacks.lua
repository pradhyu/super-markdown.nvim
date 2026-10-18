local toc = require("super-markdown.toc")

local M = {}

function M.open()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    return false, "Snacks.picker is not available"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local headings = toc.get_headings(bufnr)

  if #headings == 0 then
    vim.notify("SuperMarkdown: No headings found in buffer", vim.log.levels.WARN)
    return true
  end

  local items = {}
  for _, h in ipairs(headings) do
    table.insert(items, {
      text = h.display,
      file = filename,
      pos = { h.lnum, 1 },
      line = h.line,
      heading = h,
    })
  end

  snacks.picker({
    title = " 󰲡 Table of Contents ",
    items = items,
    format = function(item)
      return {
        { item.text, "SuperMarkdownH" .. item.heading.level },
        { string.format(" [L%d]", item.pos[1]), "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.pos then
        vim.api.nvim_win_set_cursor(0, item.pos)
        vim.cmd("normal! zvzz")
      end
    end,
  })

  return true
end

return M
