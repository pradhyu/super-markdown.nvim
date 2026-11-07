local analyzer = require("super-markdown.spec.analyzer")
local config = require("super-markdown.config")

local M = {}

--- Get active breadcrumb path for a line
--- @param bufnr number
--- @param lnum number
--- @return string breadcrumb, table path_items
function M.get_breadcrumb(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]

  local analysis = analyzer.analyze(bufnr)
  local sections = analysis.sections or {}
  local icons = config.options.render.headings.icons or { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " }

  local active_chain = {}
  for _, sec in ipairs(sections) do
    if sec.lnum <= lnum then
      while #active_chain > 0 and active_chain[#active_chain].level >= sec.level do
        table.remove(active_chain)
      end
      table.insert(active_chain, sec)
    else
      break
    end
  end

  if #active_chain == 0 then
    local doc_title = analysis.metadata and analysis.metadata.title or vim.fs.basename(analysis.filename or "Document")
    return "󰈙 " .. doc_title, {}
  end

  local parts = {}
  for _, item in ipairs(active_chain) do
    local icon = icons[item.level] or "󰲡 "
    table.insert(parts, string.format("%s%s", icon, item.title))
  end

  return table.concat(parts, " › "), active_chain
end

--- Show floating breadcrumb popup HUD
--- @param bufnr? number
function M.show_hud(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local bc_str, chain = M.get_breadcrumb(bufnr, lnum)

  local cur_sec = chain[#chain]
  local sec_info = ""
  if cur_sec and cur_sec.counts then
    local c = cur_sec.counts
    sec_info = string.format(" · %d/%d tasks · %d blockers · %d questions", c.checked or 0, c.total_tasks or 0, c.important or 0, c.question or 0)
  end

  vim.notify(string.format(" 󰈙 %s%s", bc_str, sec_info), vim.log.levels.INFO)
end

return M
