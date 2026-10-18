local tables_render = require("super-markdown.render.tables")

local M = {}

local function find_table_range(bufnr, cursor_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not tables_render.is_table_row(lines[cursor_line]) then
    return nil
  end

  local start_lnum = cursor_line
  while start_lnum > 1 and tables_render.is_table_row(lines[start_lnum - 1]) do
    start_lnum = start_lnum - 1
  end

  local end_lnum = cursor_line
  while end_lnum < #lines and tables_render.is_table_row(lines[end_lnum + 1]) do
    end_lnum = end_lnum + 1
  end

  return start_lnum, end_lnum
end

function M.format()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_lnum, end_lnum = find_table_range(bufnr, cursor[1])

  if not start_lnum then
    vim.notify("SuperMarkdown: Cursor is not inside a Markdown table", vim.log.levels.WARN)
    return
  end

  local raw_lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  local parsed_rows = {}
  local col_widths = {}
  local alignments = {}

  for row_idx, line in ipairs(raw_lines) do
    local is_sep = tables_render.is_table_separator(line)
    local raw_cells = vim.split(line:match("^%s*|(.*)|%s*$") or "", "|", { plain = true })
    local cells = {}

    for c_idx, raw_c in ipairs(raw_cells) do
      local trimmed = vim.trim(raw_c)
      table.insert(cells, trimmed)

      if is_sep then
        local left = trimmed:sub(1, 1) == ":"
        local right = trimmed:sub(-1) == ":"
        alignments[c_idx] = (left and right and "center") or (right and "right") or "left"
      else
        local len = vim.fn.strdisplaywidth(trimmed)
        col_widths[c_idx] = math.max(col_widths[c_idx] or 3, len)
      end
    end
    table.insert(parsed_rows, { cells = cells, is_sep = is_sep })
  end

  local formatted_lines = {}
  for _, row in ipairs(parsed_rows) do
    local pieces = { "" }
    for c_idx = 1, #col_widths do
      local cell = row.cells[c_idx] or ""
      local width = col_widths[c_idx] or 3

      if row.is_sep then
        local align = alignments[c_idx] or "left"
        local dashes = width
        if align == "center" then
          table.insert(pieces, ":" .. string.rep("-", math.max(1, dashes - 2)) .. ":")
        elseif align == "right" then
          table.insert(pieces, string.rep("-", math.max(1, dashes - 1)) .. ":")
        else
          table.insert(pieces, ":" .. string.rep("-", math.max(1, dashes - 1)))
        end
      else
        local pad = width - vim.fn.strdisplaywidth(cell)
        local padded = " " .. cell .. string.rep(" ", pad) .. " "
        table.insert(pieces, padded)
      end
    end
    table.insert(pieces, "")
    table.insert(formatted_lines, table.concat(pieces, "|"))
  end

  vim.api.nvim_buf_set_lines(bufnr, start_lnum - 1, end_lnum, false, formatted_lines)
  vim.notify("SuperMarkdown: Table formatted 󰄵", vim.log.levels.INFO)
end

function M.next_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  if not tables_render.is_table_row(line) then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
    return
  end

  -- Find next '|' on current line
  local next_pipe = line:find("|", col + 2, true)
  if next_pipe and next_pipe < #line then
    vim.api.nvim_win_set_cursor(0, { lnum, next_pipe + 1 })
    return
  end

  -- Move to next row
  local next_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if next_line and tables_render.is_table_row(next_line) then
    local first_pipe = next_line:find("|", 1, true)
    if first_pipe then
      vim.api.nvim_win_set_cursor(0, { lnum + 1, first_pipe + 1 })
    end
  else
    -- At the end of the table: automatically create a new row!
    local num_cols = select(2, line:gsub("|", "")) - 1
    if num_cols > 0 then
      local new_cells = {}
      for _ = 1, num_cols do
        table.insert(new_cells, "   ")
      end
      local new_row = "|" .. table.concat(new_cells, "|") .. "|"
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { new_row })
      vim.api.nvim_win_set_cursor(0, { lnum + 1, 2 })
    end
  end
end

function M.prev_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  if not tables_render.is_table_row(line) then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "n", false)
    return
  end

  -- Find previous pipe
  local prev_pipe = nil
  local pos = 1
  while true do
    local p = line:find("|", pos, true)
    if not p or p >= col then break end
    prev_pipe = p
    pos = p + 1
  end

  if prev_pipe and prev_pipe > 1 then
    vim.api.nvim_win_set_cursor(0, { lnum, prev_pipe + 1 })
    return
  end

  -- Move to previous row
  if lnum > 1 then
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 2, lnum - 1, false)[1]
    if prev_line and tables_render.is_table_row(prev_line) then
      vim.api.nvim_win_set_cursor(0, { lnum - 1, #prev_line - 2 })
    end
  end
end

return M
