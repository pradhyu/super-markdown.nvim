local config = require("super-markdown.config")
local analyzer = require("super-markdown.spec.analyzer")

local M = {}

function M.get_headings(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local headings = {}
  local icons = config.options.render.headings.icons or { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " }

  local sec_by_lnum = {}
  local ok_an, analysis = pcall(analyzer.analyze, bufnr)
  if ok_an and analysis and analysis.sections then
    for _, sec in ipairs(analysis.sections) do
      sec_by_lnum[sec.lnum] = sec
    end
  end

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
        local clean_title = vim.trim(title)

        local badge = ""
        local sec = sec_by_lnum[lnum]
        if sec and sec.counts then
          local c = sec.counts
          local parts = {}
          if c.total_tasks and c.total_tasks > 0 then
            table.insert(parts, string.format("%d/%d✓", c.checked or 0, c.total_tasks))
          end
          if c.important and c.important > 0 then
            table.insert(parts, string.format("!%d", c.important))
          end
          if c.question and c.question > 0 then
            table.insert(parts, string.format("?%d", c.question))
          end
          if #parts > 0 then
            badge = " [" .. table.concat(parts, " ") .. "]"
          end
        end

        local display = string.format("%s%s%s%s", indent, icon, clean_title, badge)

        table.insert(headings, {
          lnum = lnum,
          level = level,
          title = clean_title,
          icon = icon,
          badge = badge,
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
