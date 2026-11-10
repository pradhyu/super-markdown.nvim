local analyzer = require("super-markdown.spec.analyzer")
local skim = require("super-markdown.skim")

local M = {}

local cache = {} -- bufnr -> { text = string, last_change = number }

--- Get formatted statusline / winbar string for active markdown spec buffer
--- @param bufnr? number
--- @return string
function M.get_status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return "" end

  local ft = vim.bo[bufnr].filetype
  if ft ~= "" and ft ~= "markdown" and ft ~= "md" and ft ~= "markdown.mdx" then
    return ""
  end

  local tick = vim.b[bufnr].changedtick or 0
  local cached = cache[bufnr]
  if cached and cached.tick == tick and cached.skim == skim.is_enabled(bufnr) then
    return cached.text
  end

  local ok, analysis = pcall(analyzer.analyze, bufnr)
  if not ok or not analysis then return "" end

  local meta = analysis.metadata or {}
  local t = analysis.totals or {}
  local status_name = meta.status or "DRAFT"

  local parts = {}
  table.insert(parts, string.format("󰍔 Spec: %d%% [%s]", analysis.readiness or 100, status_name))

  if t.total_tasks and t.total_tasks > 0 then
    table.insert(parts, string.format("󰄵 %d/%d", t.checked or 0, t.total_tasks))
  end

  if t.important and t.important > 0 then
    table.insert(parts, string.format("󰀦 %d", t.important))
  end

  if t.risks and t.risks > 0 then
    table.insert(parts, string.format("󰳦 %d", t.risks))
  end

  if t.question and t.question > 0 then
    table.insert(parts, string.format("󰋽 %d", t.question))
  end

  if skim.is_enabled(bufnr) then
    table.insert(parts, "[SKIM]")
  end

  local result = table.concat(parts, " │ ")
  cache[bufnr] = {
    tick = tick,
    skim = skim.is_enabled(bufnr),
    text = result,
  }

  return result
end

return M
