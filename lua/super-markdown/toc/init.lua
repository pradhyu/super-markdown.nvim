local config = require("super-markdown.config")
local analyzer = require("super-markdown.spec.analyzer")

local M = {}

function M.resolve_markdown_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local ft = vim.bo[bufnr].filetype
    if ft == "supermarkdown_preview" or ft == "supermarkdown_toc" then
      local ok_p, pp = pcall(require, "super-markdown.preview_pane")
      if ok_p and pp.get_source_buf then
        local sbuf = pp.get_source_buf()
        if sbuf and vim.api.nvim_buf_is_valid(sbuf) then
          return sbuf
        end
      end
      local ok_s, sb = pcall(require, "super-markdown.toc.sidebar")
      if ok_s and sb.get_source_buf then
        local sbuf = sb.get_source_buf()
        if sbuf and vim.api.nvim_buf_is_valid(sbuf) then
          return sbuf
        end
      end
    end
  end
  return bufnr
end

function M.get_headings(bufnr)
  bufnr = M.resolve_markdown_buf(bufnr)
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
