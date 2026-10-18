local M = {}

function M.is_table_row(line)
  return line:match("^%s*|.-|%s*$") ~= nil
end

function M.is_table_separator(line)
  return line:match("^%s*|%s*[%:%-%s|]+%s*|%s*$") ~= nil and line:find("%-") ~= nil
end

--- Renders an entire contiguous table block with auto-alignment and box drawing
function M.render_block(bufnr, ns_id, start_lnum, end_lnum, lines, opts)
  if not (opts and opts.enabled ~= false) then return end

  local hl = opts.hl or "SuperMarkdownTableBorder"
  local head_hl = opts.header_hl or "SuperMarkdownTableHeader"
  local c = opts.corners or {
    top_left = "┌", top_mid = "┬", top_right = "┐",
    mid_left = "├", mid_mid = "┼", mid_right = "┤",
    bot_left = "└", bot_mid = "┴", bot_right = "┘",
  }
  local head_sep = opts.head_sep or "─"
  local vertical = opts.vertical or "│"

  -- 1. Parse rows and find separator row
  local sep_idx = nil
  local rows = {}

  for lnum = start_lnum, end_lnum do
    local line = lines[lnum + 1]
    local is_sep = M.is_table_separator(line)
    if is_sep and not sep_idx then
      sep_idx = lnum
    end

    local pipes = {}
    local p = 0
    while true do
      p = line:find("|", p + 1, true)
      if not p then break end
      table.insert(pipes, p)
    end

    local cells = {}
    for i = 1, #pipes - 1 do
      local p_start = pipes[i]
      local p_end = pipes[i + 1]
      local raw = line:sub(p_start + 1, p_end - 1)
      local trimmed = vim.trim(raw)
      local lead_sp = raw:match("^(%s*)") or ""
      local trail_sp = raw:match("(%s*)$") or ""
      table.insert(cells, {
        raw = raw,
        trimmed = trimmed,
        lead_len = #lead_sp,
        trail_len = #trail_sp,
        width = vim.fn.strdisplaywidth(trimmed),
        p_start = p_start,
        p_end = p_end,
      })
    end

    table.insert(rows, {
      lnum = lnum,
      line = line,
      is_sep = is_sep,
      pipes = pipes,
      cells = cells,
    })
  end

  if #rows == 0 then return end

  -- Parse column alignments from separator
  local num_cols = 0
  for _, r in ipairs(rows) do
    if #r.cells > num_cols then num_cols = #r.cells end
  end

  local aligns = {}
  if sep_idx then
    local sep_row = rows[sep_idx - start_lnum + 1]
    for i = 1, num_cols do
      local c_cell = sep_row and sep_row.cells[i]
      if c_cell then
        local t = c_cell.trimmed
        local left_colon = t:sub(1, 1) == ":"
        local right_colon = t:sub(-1) == ":"
        if left_colon and right_colon then
          aligns[i] = "center"
        elseif right_colon then
          aligns[i] = "right"
        else
          aligns[i] = "left"
        end
      else
        aligns[i] = "left"
      end
    end
  else
    for i = 1, num_cols do aligns[i] = "left" end
  end

  -- Compute max column widths (ignoring separator row)
  local col_widths = {}
  for i = 1, num_cols do col_widths[i] = 3 end
  for _, r in ipairs(rows) do
    if not r.is_sep then
      for i, cell in ipairs(r.cells) do
        if cell.width > col_widths[i] then
          col_widths[i] = cell.width
        end
      end
    end
  end

  -- A. Render Top Border
  local top_pieces = { { c.top_left, hl } }
  for i = 1, num_cols do
    table.insert(top_pieces, { string.rep(head_sep, col_widths[i] + 2), hl })
    table.insert(top_pieces, { (i < num_cols) and c.top_mid or c.top_right, hl })
  end

  if start_lnum > 0 then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, start_lnum - 1, 0, {
      virt_lines = { top_pieces },
      virt_lines_above = false,
      priority = 95,
    })
  else
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, 0, 0, {
      virt_lines = { top_pieces },
      virt_lines_above = true,
      priority = 95,
    })
  end

  -- B. Render Rows
  for _, r in ipairs(rows) do
    local lnum = r.lnum
    local is_header = sep_idx and (lnum < sep_idx)

    if r.is_sep then
      -- Delimiter row
      local delim_pieces = { { c.mid_left, hl } }
      for i = 1, num_cols do
        local align = aligns[i]
        local w = col_widths[i]
        local seg
        if align == "center" then
          seg = ":" .. string.rep(head_sep, math.max(0, w)) .. ":"
        elseif align == "right" then
          seg = string.rep(head_sep, w + 1) .. ":"
        else
          seg = ":" .. string.rep(head_sep, w + 1)
        end
        table.insert(delim_pieces, { seg, hl })
        table.insert(delim_pieces, { (i < num_cols) and c.mid_mid or c.mid_right, hl })
      end

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
        end_col = #r.line,
        conceal = "",
        virt_text = delim_pieces,
        virt_text_pos = "overlay",
        priority = 100,
      })
    else
      -- Data or Header Row
      for i = 1, #r.pipes - 1 do
        local cell = r.cells[i]
        local p_start = cell.p_start
        local p_end = cell.p_end
        local target = col_widths[i]
        local pad = target - cell.width
        local align = aligns[i]

        local pad_l, pad_r = 0, pad
        if align == "right" then
          pad_l, pad_r = pad, 0
        elseif align == "center" then
          pad_l = math.floor(pad / 2)
          pad_r = pad - pad_l
        end

        -- Replace left pipe
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, p_start - 1, {
          end_col = p_start,
          virt_text = { { vertical, hl } },
          virt_text_pos = "overlay",
          priority = 90,
        })

        -- Inline padding adjustments
        local need_lead = (1 + pad_l) - cell.lead_len
        local need_trail = (1 + pad_r) - cell.trail_len

        if need_lead > 0 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, p_start, {
            virt_text = { { string.rep(" ", need_lead), is_header and head_hl or "Normal" } },
            virt_text_pos = "inline",
            priority = 85,
          })
        elseif need_lead < 0 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, p_start, {
            end_col = p_start + (-need_lead),
            conceal = "",
            priority = 85,
          })
        end

        if need_trail > 0 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, p_end - 1, {
            virt_text = { { string.rep(" ", need_trail), is_header and head_hl or "Normal" } },
            virt_text_pos = "inline",
            priority = 85,
          })
        elseif need_trail < 0 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, p_end - 1 + need_trail, {
            end_col = p_end - 1,
            conceal = "",
            priority = 85,
          })
        end
      end

      -- Replace last pipe
      if #r.pipes > 0 then
        local last_p = r.pipes[#r.pipes]
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, last_p - 1, {
          end_col = last_p,
          virt_text = { { vertical, hl } },
          virt_text_pos = "overlay",
          priority = 90,
        })
      end
    end
  end

  -- C. Render Bottom Border
  local bot_pieces = { { c.bot_left, hl } }
  for i = 1, num_cols do
    table.insert(bot_pieces, { string.rep(head_sep, col_widths[i] + 2), hl })
    table.insert(bot_pieces, { (i < num_cols) and c.bot_mid or c.bot_right, hl })
  end

  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, end_lnum, 0, {
    virt_lines = { bot_pieces },
    virt_lines_above = false,
    priority = 95,
  })
end

--- Backward compatibility single-row render fallback
function M.render(bufnr, ns_id, lnum, line, prev_is_table, next_is_table, opts)
  if not (opts and opts.enabled ~= false) then return end
  if not M.is_table_row(line) then return end

  local hl = opts.hl or "SuperMarkdownTableBorder"
  local c = opts.corners or {
    top_left = "┌", top_mid = "┬", top_right = "┐",
    mid_left = "├", mid_mid = "┼", mid_right = "┤",
    bot_left = "└", bot_mid = "┴", bot_right = "┘",
  }

  if M.is_table_separator(line) then
    local indent = line:match("^(%s*)") or ""
    local segments = vim.split(line:match("^%s*|(.*)|%s*$") or "", "|", { plain = true })
    local pieces = { { indent .. c.mid_left, hl } }
    for i, seg in ipairs(segments) do
      local len = vim.fn.strdisplaywidth(seg)
      table.insert(pieces, { string.rep(opts.head_sep or "─", len), hl })
      table.insert(pieces, { (i < #segments) and c.mid_mid or c.mid_right, hl })
    end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
      end_col = #line,
      conceal = "",
      virt_text = pieces,
      virt_text_pos = "overlay",
      priority = 100,
    })
    return
  end

  local col = 0
  while true do
    local pipe_pos = line:find("|", col + 1, true)
    if not pipe_pos then break end
    col = pipe_pos
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, col - 1, {
      end_col = col,
      conceal = "",
      virt_text = { { opts.vertical or "│", hl } },
      virt_text_pos = "overlay",
      priority = 90,
    })
  end
end

return M
