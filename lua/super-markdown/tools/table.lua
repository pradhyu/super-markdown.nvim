local tables_render = require("super-markdown.render.tables")

local M = {}

local function find_table_range(bufnr, cursor_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not lines[cursor_line] or not tables_render.is_table_row(lines[cursor_line]) then
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

local function split_row_cells(line)
  local pipes = tables_render.find_unescaped_pipes(line)
  local cells = {}
  for i = 1, #pipes - 1 do
    local raw = line:sub(pipes[i] + 1, pipes[i + 1] - 1)
    table.insert(cells, vim.trim(raw))
  end
  return cells, pipes
end

function M.format(opts)
  opts = opts or {}
  local silent = opts.silent == true
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].modifiable then
    return false
  end

  local win = vim.fn.bufwinid(bufnr)
  local cursor = (win and win ~= -1) and vim.api.nvim_win_get_cursor(win) or vim.api.nvim_win_get_cursor(0)
  local target_lnum = opts.lnum or cursor[1]
  local start_lnum, end_lnum = find_table_range(bufnr, target_lnum)

  if not start_lnum then
    if not silent then
      vim.notify("SuperMarkdown: Cursor is not inside a Markdown table", vim.log.levels.WARN)
    end
    return false
  end

  local raw_lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  local parsed_rows = {}
  local col_widths = {}
  local alignments = {}
  local num_cols = 0

  for _, line in ipairs(raw_lines) do
    local is_sep = tables_render.is_table_separator(line)
    local cells = split_row_cells(line)
    if #cells > num_cols then
      num_cols = #cells
    end

    for c_idx, trimmed in ipairs(cells) do
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

  for c_idx = 1, num_cols do
    col_widths[c_idx] = col_widths[c_idx] or 3
  end

  local formatted_lines = {}
  local changed = false
  for r_idx, row in ipairs(parsed_rows) do
    local indent = raw_lines[r_idx]:match("^(%s*)") or ""
    local pieces = { indent }
    for c_idx = 1, num_cols do
      local cell = row.cells[c_idx] or ""
      local width = col_widths[c_idx] or 3

      if row.is_sep then
        local align = alignments[c_idx] or "left"
        local dashes = width
        if align == "center" then
          table.insert(pieces, " :" .. string.rep("-", math.max(3, dashes - 2)) .. ": ")
        elseif align == "right" then
          table.insert(pieces, " " .. string.rep("-", math.max(3, dashes - 1)) .. ": ")
        else
          table.insert(pieces, " :" .. string.rep("-", math.max(3, dashes - 1)) .. " ")
        end
      else
        local align = alignments[c_idx] or "left"
        local pad = math.max(0, width - vim.fn.strdisplaywidth(cell))
        local pad_l, pad_r = 0, pad
        if align == "right" then
          pad_l, pad_r = pad, 0
        elseif align == "center" then
          pad_l = math.floor(pad / 2)
          pad_r = pad - pad_l
        end
        local padded = " " .. string.rep(" ", pad_l) .. cell .. string.rep(" ", pad_r) .. " "
        table.insert(pieces, padded)
      end
    end
    table.insert(pieces, "")
    local new_line = table.concat(pieces, "|")
    if new_line ~= raw_lines[r_idx] then
      changed = true
    end
    table.insert(formatted_lines, new_line)
  end

  if changed then
    -- Preserve approximate cell index for cursor if inside the formatted table
    local cur_line_idx = cursor[1] - start_lnum + 1
    local cur_cell_idx = 1
    if cur_line_idx >= 1 and cur_line_idx <= #raw_lines then
      local _, old_pipes = split_row_cells(raw_lines[cur_line_idx])
      for i = 1, #old_pipes - 1 do
        if cursor[2] + 1 >= old_pipes[i] then
          cur_cell_idx = i
        end
      end
    end

    vim.api.nvim_buf_set_lines(bufnr, start_lnum - 1, end_lnum, false, formatted_lines)

    if win and win ~= -1 and cur_line_idx >= 1 and cur_line_idx <= #formatted_lines then
      local new_row = formatted_lines[cur_line_idx]
      local new_pipes = tables_render.find_unescaped_pipes(new_row)
      local target_pipe = new_pipes[math.min(cur_cell_idx, #new_pipes)]
      if target_pipe then
        local new_col = math.min(#new_row - 1, target_pipe + 1)
        pcall(vim.api.nvim_win_set_cursor, win, { cursor[1], math.max(0, new_col) })
      end
    end
  end

  if not silent then
    vim.notify("SuperMarkdown: Table formatted 󰄵", vim.log.levels.INFO)
  end
  return changed
end

function M.format_all(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].modifiable then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local in_codeblock = false
  local lnum = 1
  local any_changed = false

  while lnum <= #lines do
    local line = lines[lnum]
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_codeblock = not in_codeblock
      lnum = lnum + 1
    elseif not in_codeblock and tables_render.is_table_row(line) then
      local changed = M.format({ bufnr = bufnr, lnum = lnum, silent = true })
      if changed then
        any_changed = true
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      end
      while lnum <= #lines and tables_render.is_table_row(lines[lnum]) do
        lnum = lnum + 1
      end
    else
      lnum = lnum + 1
    end
  end

  return any_changed
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

  -- Auto-format table quietly before moving to the next cell
  local config = require("super-markdown.config")
  if config.options.tools and config.options.tools.auto_format_table ~= false then
    M.format({ bufnr = bufnr, lnum = lnum, silent = true })
    cursor = vim.api.nvim_win_get_cursor(0)
    lnum, col = cursor[1], cursor[2]
    line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  end

  local pipes = tables_render.find_unescaped_pipes(line)
  for _, p in ipairs(pipes) do
    if p > col + 1 and p < pipes[#pipes] then
      vim.api.nvim_win_set_cursor(0, { lnum, p + 1 })
      return
    end
  end

  -- Move to next row
  local next_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if next_line and tables_render.is_table_row(next_line) then
    local next_pipes = tables_render.find_unescaped_pipes(next_line)
    if next_pipes[1] then
      vim.api.nvim_win_set_cursor(0, { lnum + 1, next_pipes[1] + 1 })
    end
  else
    -- At the end of the table: automatically create a new row!
    local num_cols = #pipes - 1
    if num_cols > 0 then
      local new_cells = {}
      for _ = 1, num_cols do
        table.insert(new_cells, "   ")
      end
      local new_row = "|" .. table.concat(new_cells, "|") .. "|"
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { new_row })
      if config.options.tools and config.options.tools.auto_format_table ~= false then
        M.format({ bufnr = bufnr, lnum = lnum + 1, silent = true })
      end
      local updated = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or new_row
      local u_pipes = tables_render.find_unescaped_pipes(updated)
      vim.api.nvim_win_set_cursor(0, { lnum + 1, (u_pipes[1] or 1) + 1 })
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

  local config = require("super-markdown.config")
  if config.options.tools and config.options.tools.auto_format_table ~= false then
    M.format({ bufnr = bufnr, lnum = lnum, silent = true })
    cursor = vim.api.nvim_win_get_cursor(0)
    lnum, col = cursor[1], cursor[2]
    line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  end

  -- Find previous pipe
  local pipes = tables_render.find_unescaped_pipes(line)
  local prev_pipe = nil
  for _, p in ipairs(pipes) do
    if p >= col then break end
    prev_pipe = p
  end

  if prev_pipe and prev_pipe > (pipes[1] or 1) then
    vim.api.nvim_win_set_cursor(0, { lnum, prev_pipe + 1 })
    return
  end

  -- Move to previous row
  if lnum > 1 then
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 2, lnum - 1, false)[1]
    if prev_line and tables_render.is_table_row(prev_line) then
      local prev_pipes = tables_render.find_unescaped_pipes(prev_line)
      if #prev_pipes >= 2 then
        vim.api.nvim_win_set_cursor(0, { lnum - 1, prev_pipes[#prev_pipes - 1] + 1 })
      else
        vim.api.nvim_win_set_cursor(0, { lnum - 1, #prev_line - 2 })
      end
    end
  end
end

return M
