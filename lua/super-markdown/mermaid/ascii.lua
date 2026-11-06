local M = {}

local function str_width(s)
  return vim.fn.strdisplaywidth(s or "")
end

local function pad_str(s, width, align)
  local len = str_width(s)
  if len >= width then
    return s
  end
  local diff = width - len
  if align == "right" then
    return string.rep(" ", diff) .. s
  elseif align == "center" then
    local left = math.floor(diff / 2)
    local right = diff - left
    return string.rep(" ", left) .. s .. string.rep(" ", right)
  else
    return s .. string.rep(" ", diff)
  end
end

local function truncate_str(s, max_w)
  if not s then
    return ""
  end
  if str_width(s) <= max_w then
    return s
  end
  if max_w <= 1 then
    return "…"
  end
  local out = ""
  local chars = vim.fn.strchars(s)
  for idx = 0, chars - 1 do
    local ch = vim.fn.strcharpart(s, idx, 1)
    if str_width(out .. ch) + 1 > max_w then
      break
    end
    out = out .. ch
  end
  return out .. "…"
end

--- Strip outer quotes, unescape HTML/Mermaid entities, and split `<br/>` into lines
local function clean_label_lines(raw)
  if not raw or raw == "" then
    return {}
  end
  local s = vim.trim(raw)
  if (s:sub(1, 1) == '"' and s:sub(-1) == '"') or (s:sub(1, 1) == "'" and s:sub(-1) == "'") then
    s = s:sub(2, -2)
  end
  s = s:gsub('\\"', '"')
  s = s:gsub("#quot;", '"')
  s = s:gsub("&quot;", '"')
  s = s:gsub("<br%s*/?>", "\n")
  s = s:gsub("\\n", "\n")
  local parts = vim.split(s, "\n", { plain = true })
  local out = {}
  for _, p in ipairs(parts) do
    local t = vim.trim(p)
    if t ~= "" then
      table.insert(out, t)
    end
  end
  return out
end

--- Word-wrap a list of label lines so each line fits within `max_line_w` (up to `max_lines`)
local function wrap_label_lines(lines, max_line_w, max_lines)
  if not max_line_w or max_line_w < 8 then
    return lines
  end
  max_lines = max_lines or 3
  local wrapped = {}
  for _, line in ipairs(lines) do
    if str_width(line) <= max_line_w then
      table.insert(wrapped, line)
    else
      local words = vim.split(line, "%s+")
      local cur = ""
      for _, w in ipairs(words) do
        if cur == "" then
          cur = w
        elseif str_width(cur) + 1 + str_width(w) <= max_line_w then
          cur = cur .. " " .. w
        else
          table.insert(wrapped, truncate_str(cur, max_line_w))
          cur = w
        end
      end
      if cur ~= "" then
        table.insert(wrapped, truncate_str(cur, max_line_w))
      end
    end
  end
  if #wrapped > max_lines then
    local capped = {}
    for i = 1, max_lines - 1 do
      capped[i] = wrapped[i]
    end
    local rest = table.concat(wrapped, " ", max_lines)
    capped[max_lines] = truncate_str(rest, max_line_w)
    return capped
  end
  return wrapped
end

--- Parse a single Mermaid node token like `A["Label (extra)"]`, `B{Choice?}`, `C[(Database)]`, `D([Stadium])`
local function parse_node(str)
  if not str then
    return nil
  end
  local s = vim.trim(str)
  if s == "" then
    return nil
  end
  -- Strip trailing :::className or ;
  s = s:gsub(":::[%w_%-]+%s*$", "")
  s = s:gsub(";%s*$", "")
  s = vim.trim(s)

  local id, rest = s:match("^([%w_%-%.]+)%s*(.*)$")
  if not id then
    -- Quoted node ID
    id, rest = s:match('^"([^"]+)"%s*(.*)$')
  end
  if not id then
    return nil
  end
  rest = vim.trim(rest or "")
  if rest == "" then
    return id, nil, nil
  end

  local shape, inner
  if rest:match("^%[%((.*)%)]$") then
    shape = "database"
    inner = rest:match("^%[%((.*)%)]$")
  elseif rest:match("^%(%[(.*)%)]$") then
    shape = "stadium"
    inner = rest:match("^%(%[(.*)%)]$")
  elseif rest:match("^%(%((.*)%)%)$") then
    shape = "circle"
    inner = rest:match("^%(%((.*)%)%)$")
  elseif rest:match("^%{%{(.*)%}%}$") then
    shape = "hexagon"
    inner = rest:match("^%{%{(.*)%}%}$")
  elseif rest:match("^%[%[(.*)%]%]$") then
    shape = "subroutine"
    inner = rest:match("^%[%[(.*)%]%]$")
  elseif rest:match("^%[(.*)%]$") then
    shape = "rectangle"
    inner = rest:match("^%[(.*)%]$")
  elseif rest:match("^%((.*)%)$") then
    shape = "rounded"
    inner = rest:match("^%((.*)%)$")
  elseif rest:match("^%{(.*)%}$") then
    shape = "decision"
    inner = rest:match("^%{(.*)%}$")
  elseif rest:match("^>(.*)%]$") then
    shape = "asymmetric"
    inner = rest:match("^>(.*)%]$")
  else
    return id, nil, nil
  end

  local lines = clean_label_lines(inner)
  local label = (#lines > 0) and table.concat(lines, "\n") or id
  return id, shape, label
end

--- Render a multi-line Unicode box for a node
local function make_box(id, shape, text, max_box_w)
  local raw_lines = (text and text ~= "") and vim.split(text, "\n", { plain = true }) or { id }
  local max_inner_w = max_box_w and math.max(10, max_box_w - 4) or 46
  local lines = wrap_label_lines(raw_lines, max_inner_w, 3)
  if #lines == 0 then
    lines = { id }
  end

  local inner_w = 4
  for _, l in ipairs(lines) do
    local lw = str_width(l)
    if lw > inner_w then
      inner_w = lw
    end
  end

  local box_lines = {}
  local top, bot
  local l_border, r_border = "│ ", " │"

  if shape == "database" then
    local tag = "[(db)]"
    local dash_total = math.max(2, inner_w + 2 - str_width(tag))
    local d_left = math.floor(dash_total / 2)
    local d_right = dash_total - d_left
    top = "╭" .. string.rep("─", d_left) .. tag .. string.rep("─", d_right) .. "╮"
    bot = "╰" .. string.rep("─", inner_w + 2) .. "╯"
  elseif shape == "decision" then
    top = "◇" .. string.rep("─", inner_w + 2) .. "◇"
    bot = "◇" .. string.rep("─", inner_w + 2) .. "◇"
  elseif shape == "hexagon" then
    top = "╱" .. string.rep("─", inner_w + 2) .. "╲"
    bot = "╲" .. string.rep("─", inner_w + 2) .. "╱"
  elseif shape == "subroutine" then
    top = "┌" .. string.rep("─", inner_w + 2) .. "┐"
    bot = "└" .. string.rep("─", inner_w + 2) .. "┘"
    l_border, r_border = "║ ", " ║"
  elseif shape == "rounded" or shape == "stadium" or shape == "circle" then
    top = "╭" .. string.rep("─", inner_w + 2) .. "╮"
    bot = "╰" .. string.rep("─", inner_w + 2) .. "╯"
  else
    top = "┌" .. string.rep("─", inner_w + 2) .. "┐"
    bot = "└" .. string.rep("─", inner_w + 2) .. "┘"
  end

  table.insert(box_lines, top)
  for _, l in ipairs(lines) do
    table.insert(box_lines, l_border .. pad_str(l, inner_w, "center") .. r_border)
  end
  table.insert(box_lines, bot)

  local total_w = str_width(top)
  return {
    lines = box_lines,
    top = box_lines[1],
    mid = box_lines[2] or box_lines[1],
    bot = box_lines[#box_lines],
    height = #box_lines,
    width = total_w,
    label = table.concat(lines, " "),
  }
end

--- Frame lines inside a Unicode border card
local function frame_diagram(lines, title, opts)
  opts = opts or {}
  if opts.bare then
    return lines
  end
  local max_w = str_width(title) + 6
  for _, l in ipairs(lines) do
    local w = str_width(l)
    if w > max_w then
      max_w = w
    end
  end
  max_w = math.max(max_w + 4, 44)
  if opts.max_width and opts.max_width > 20 then
    max_w = math.max(max_w, math.min(opts.max_width - 4, max_w))
  end

  local header_bar = "┌─ " .. title .. " " .. string.rep("─", math.max(0, max_w - str_width(title) - 4)) .. "┐"
  local footer_bar = "└" .. string.rep("─", max_w) .. "┘"
  local empty_line = "│" .. string.rep(" ", max_w) .. "│"

  local result = {}
  table.insert(result, header_bar)
  table.insert(result, empty_line)

  for _, l in ipairs(lines) do
    local diff = max_w - str_width(l) - 2
    local right_pad = diff > 0 and string.rep(" ", diff) or ""
    table.insert(result, "│  " .. l .. right_pad .. "│")
  end

  table.insert(result, empty_line)
  table.insert(result, footer_bar)
  return result
end

-- =========================================================================
-- 1. SEQUENCE DIAGRAM RENDERER
-- =========================================================================
local function render_sequence(code, opts)
  opts = opts or {}
  local max_width = opts.max_width
  local lines = vim.split(code, "\n")
  local participants = {}
  local p_lookup = {}
  local messages = {}
  local autonumber = false
  local step = 0

  local function ensure_participant(raw_id, as_name, p_type)
    local id = vim.trim(raw_id or "")
    if (id:sub(1, 1) == '"' and id:sub(-1) == '"') or (id:sub(1, 1) == "'" and id:sub(-1) == "'") then
      id = id:sub(2, -2)
    end
    if id == "" then
      return nil
    end
    if not p_lookup[id] then
      local disp = vim.trim(as_name or id)
      if (disp:sub(1, 1) == '"' and disp:sub(-1) == '"') or (disp:sub(1, 1) == "'" and disp:sub(-1) == "'") then
        disp = disp:sub(2, -2)
      end
      disp = disp:gsub("<br%s*/?>", " ")
      table.insert(participants, { id = id, name = disp, type = p_type or "participant" })
      p_lookup[id] = #participants
    elseif as_name and as_name ~= "" then
      local disp = vim.trim(as_name)
      if (disp:sub(1, 1) == '"' and disp:sub(-1) == '"') or (disp:sub(1, 1) == "'" and disp:sub(-1) == "'") then
        disp = disp:sub(2, -2)
      end
      participants[p_lookup[id]].name = disp:gsub("<br%s*/?>", " ")
    end
    return id
  end

  for _, raw_line in ipairs(lines) do
    local line = vim.trim(raw_line)
    if line == "" or line:match("^%%") or line:match("^sequenceDiagram") then
      -- skip
    elseif line:match("^autonumber") then
      autonumber = true
    elseif line:match("^actor%s+") or line:match("^participant%s+") then
      local p_type = line:match("^(%w+)")
      local rest = vim.trim(line:gsub("^%w+%s+", ""))
      local id, as_name = rest:match('^"([^"]+)"%s+as%s+(.+)$')
      if not id then
        id, as_name = rest:match("^([%w_%-%.]+)%s+as%s+(.+)$")
      end
      if not id then
        id = rest:match('^"([^"]+)"$') or rest:match("^([%w_%-%.]+)$") or rest
        as_name = id
      end
      ensure_participant(id, as_name, p_type)
    elseif line:lower():match("^note%s+") then
      local pos, targets, note_txt = line:match("^[Nn]ote%s+([%w%s]+)%s+([^:]+):%s*(.+)$")
      if note_txt then
        table.insert(messages, {
          note = vim.trim(note_txt):gsub("<br%s*/?>", " "),
          note_targets = vim.trim(targets or ""),
          note_pos = vim.trim(pos or ""),
        })
      else
        table.insert(messages, { block = line })
      end
    elseif
      line:match("^alt%s*")
      or line:match("^else%s*")
      or line:match("^opt%s*")
      or line:match("^loop%s*")
      or line:match("^par%s*")
      or line:match("^and%s*")
      or line:match("^critical%s*")
      or line:match("^break%s*")
      or line:match("^rect%s*")
      or line == "end"
    then
      table.insert(messages, { block = line })
    elseif not (line:match("^activate%s+") or line:match("^deactivate%s+") or line:match("^box%s+")) then
      -- Match sequence message arrows including activation +/- and spaces like `-- >>`
      local lhs, rhs_text = line:match("^(.-)%s*:%s*(.+)$")
      if lhs and rhs_text then
        -- Normalize spaces inside arrows like `-- >>` -> `-->>`
        local norm_lhs = lhs:gsub("([%-%.=])%s+([>%)x])", "%1%2")
        local from_raw, arrow, to_raw =
          norm_lhs:match("^(.-)%s*(<?<?[%-%.=]+>>?[x%)%+%-]*)%s*([%w_%-%.%s\"']+)$")
        if not from_raw then
          from_raw, arrow, to_raw = norm_lhs:match("^(.-)%s*([%-%.=]+[>x%)][%+%-]?)%s*([%w_%-%.%s\"']+)$")
        end
        if from_raw and arrow and to_raw then
          local from_id = ensure_participant(from_raw)
          local to_id = ensure_participant(to_raw)
          if from_id and to_id then
            step = step + 1
            table.insert(messages, {
              from = from_id,
              to = to_id,
              arrow = arrow,
              text = vim.trim(rhs_text):gsub("<br%s*/?>", " "),
              step = autonumber and step or nil,
            })
          end
        end
      end
    end
  end

  if #participants == 0 then
    return frame_diagram({ "(Empty sequence diagram)" }, "󰡷 Mermaid Sequence Diagram", opts)
  end

  local n_p = #participants
  local gap_w = 5
  local col_widths = {}
  local disp_names = {}
  for i, p in ipairs(participants) do
    local prefix = (p.type == "actor") and "󰀄 " or ""
    local name = prefix .. p.name
    col_widths[i] = math.max(str_width(name) + 4, 14)
    disp_names[i] = name
  end

  for _, m in ipairs(messages) do
    if m.from and m.to then
      local f_i = p_lookup[m.from]
      local t_i = p_lookup[m.to]
      if f_i and t_i and f_i ~= t_i and math.abs(t_i - f_i) == 1 then
        local min_i = math.min(f_i, t_i)
        local lbl_w = str_width((m.step and (m.step .. ". ") or "") .. m.text) + 4
        local cur_span = math.floor(col_widths[min_i] / 2) + gap_w + math.floor(col_widths[min_i + 1] / 2)
        if lbl_w > cur_span then
          local extra = math.min(16, lbl_w - cur_span)
          col_widths[min_i] = col_widths[min_i] + math.ceil(extra / 2)
          col_widths[min_i + 1] = col_widths[min_i + 1] + math.floor(extra / 2)
        end
      end
    end
  end

  if max_width and max_width > 24 then
    local total_w = (n_p - 1) * gap_w
    for i = 1, n_p do
      total_w = total_w + col_widths[i]
    end
    if total_w > max_width then
      gap_w = math.max(2, math.min(gap_w, math.floor((max_width - n_p * 10) / math.max(1, n_p - 1))))
      local avail_boxes = math.max(n_p * 8, max_width - (n_p - 1) * gap_w)
      local base_w = math.max(8, math.floor(avail_boxes / n_p))
      for i, _ in ipairs(participants) do
        col_widths[i] = math.min(col_widths[i], base_w)
        disp_names[i] = truncate_str(disp_names[i], math.max(4, col_widths[i] - 2))
      end
    end
  end

  local col_gap = string.rep(" ", gap_w)

  local centers = {}
  local offset = 0
  for i = 1, n_p do
    local half = math.floor(col_widths[i] / 2)
    centers[i] = offset + half
    offset = offset + col_widths[i] + ((i < n_p) and gap_w or 0)
  end
  local total_grid_w = offset

  local function render_grid_row(overlay_col, overlay_str)
    local cells = {}
    for c = 0, total_grid_w - 1 do
      cells[c] = " "
    end
    for i = 1, n_p do
      cells[centers[i]] = "│"
    end
    if overlay_col and overlay_str then
      local n_chars = vim.fn.strchars(overlay_str)
      local c = overlay_col
      for idx = 0, n_chars - 1 do
        local ch = vim.fn.strcharpart(overlay_str, idx, 1)
        local cw = math.max(1, str_width(ch))
        if c >= 0 then
          cells[c] = ch
          for k = 1, cw - 1 do
            cells[c + k] = ""
          end
        end
        c = c + cw
      end
    end
    local max_c = total_grid_w - 1
    if overlay_col and overlay_str then
      max_c = math.max(max_c, overlay_col + str_width(overlay_str) - 1)
    end
    local row_out = {}
    for c = 0, max_c do
      if cells[c] and cells[c] ~= "" then
        table.insert(row_out, cells[c])
      end
    end
    return (table.concat(row_out):gsub("%s+$", ""))
  end

  local h_top_parts, h_mid_parts, h_bot_parts, f_top_parts = {}, {}, {}, {}
  for i = 1, n_p do
    local w = col_widths[i]
    local half = math.floor(w / 2)
    local r_len = math.max(0, w - 2 - half)
    table.insert(h_top_parts, "╭" .. string.rep("─", w - 2) .. "╮")
    table.insert(h_mid_parts, "│" .. pad_str(disp_names[i], w - 2, "center") .. "│")
    table.insert(h_bot_parts, "╰" .. string.rep("─", math.max(0, half - 1)) .. "┬" .. string.rep("─", r_len) .. "╯")
    table.insert(f_top_parts, "╭" .. string.rep("─", math.max(0, half - 1)) .. "┴" .. string.rep("─", r_len) .. "╮")
  end

  local h_top = table.concat(h_top_parts, col_gap)
  local h_mid = table.concat(h_mid_parts, col_gap)
  local h_bot = table.concat(h_bot_parts, col_gap)
  local f_top = table.concat(f_top_parts, col_gap)
  local f_bot = table.concat(
    vim.tbl_map(function(w)
      return "╰" .. string.rep("─", w - 2) .. "╯"
    end, col_widths),
    col_gap
  )

  local out = { h_top, h_mid, h_bot, render_grid_row() }

  for _, m in ipairs(messages) do
    if m.note then
      local note_str = "󰋽 [" .. m.note .. "]"
      if max_width and max_width > 14 then
        note_str = truncate_str(note_str, max_width - 4)
      end
      local target_col = math.max(0, centers[1] - 1)
      if m.note_targets then
        local first_t = vim.trim(vim.split(m.note_targets, ",")[1] or "")
        if p_lookup[first_t] then
          target_col = math.max(0, centers[p_lookup[first_t]] - 2)
        end
      end
      table.insert(out, render_grid_row(target_col, note_str))
      table.insert(out, render_grid_row())
    elseif m.block then
      local blk_str = "┈ [" .. m.block .. "] ┈"
      if max_width and max_width > 14 then
        blk_str = truncate_str(blk_str, max_width - 4)
      end
      table.insert(out, render_grid_row(math.max(0, centers[1] - 1), blk_str))
      table.insert(out, render_grid_row())
    else
      local from_idx = p_lookup[m.from]
      local to_idx = p_lookup[m.to]
      local label = (m.step and (m.step .. ". ") or "") .. m.text

      if from_idx == to_idx then
        local c_pos = centers[from_idx]
        local avail_lbl = (from_idx < n_p) and math.max(8, centers[from_idx + 1] - c_pos - 6)
          or (max_width and math.max(10, max_width - c_pos - 6) or 36)
        local clean_lbl = truncate_str(label, avail_lbl)
        table.insert(out, render_grid_row(c_pos, "├──╮ " .. clean_lbl))
        table.insert(out, render_grid_row(c_pos, "│◀─╯"))
      else
        local min_idx = math.min(from_idx, to_idx)
        local max_idx = math.max(from_idx, to_idx)
        local ltr = (from_idx < to_idx)
        local c_left = centers[min_idx]
        local c_right = centers[max_idx]
        local span_w = math.max(3, c_right - c_left - 1)

        -- Allow multi-line message label if it's longer than span_w
        local msg_lines = wrap_label_lines({ label }, math.max(8, span_w - 2), 2)
        for _, ml in ipairs(msg_lines) do
          local lbl_col = c_left + 1 + math.max(0, math.floor((span_w - str_width(ml)) / 2))
          table.insert(out, render_grid_row(lbl_col, ml))
        end

        local is_dashed = m.arrow:find("%-%.") ~= nil or m.arrow:find("%-%-") ~= nil
        local dash_unit = is_dashed and "╌" or "─"
        local shaft = string.rep(dash_unit, math.max(1, span_w - 1))
        local arr_overlay = ltr and ("├" .. shaft .. "▶│") or ("│◀" .. shaft .. "┤")
        table.insert(out, render_grid_row(c_left, arr_overlay))
      end

      table.insert(out, render_grid_row())
    end
  end

  table.insert(out, f_top)
  table.insert(out, h_mid)
  table.insert(out, f_bot)

  return frame_diagram(out, "󰡷 Mermaid Sequence Diagram (Live)", opts)
end

-- =========================================================================
-- 2. FLOWCHART / GRAPH & STATE 2D LAYERED ENGINE
-- =========================================================================

--- Split a single flowchart line into node groups and arrow operators at bracket/quote depth 0
local function parse_flowchart_statement(line)
  local len = #line
  local i = 1
  local depth_sq, depth_rd, depth_cu = 0, 0, 0
  local in_quote = nil
  local tokens = {} -- alternating: node_expr, { arrow = ..., label = ... }, node_expr, ...
  local seg_start = 1

  while i <= len do
    local ch = line:sub(i, i)
    if in_quote then
      if ch == "\\" then
        i = i + 2
      elseif ch == in_quote then
        in_quote = nil
        i = i + 1
      else
        i = i + 1
      end
    else
      if ch == '"' or ch == "'" then
        in_quote = ch
        i = i + 1
      elseif ch == "[" then
        depth_sq = depth_sq + 1
        i = i + 1
      elseif ch == "]" then
        depth_sq = math.max(0, depth_sq - 1)
        i = i + 1
      elseif ch == "(" then
        depth_rd = depth_rd + 1
        i = i + 1
      elseif ch == ")" then
        depth_rd = math.max(0, depth_rd - 1)
        i = i + 1
      elseif ch == "{" then
        depth_cu = depth_cu + 1
        i = i + 1
      elseif ch == "}" then
        depth_cu = math.max(0, depth_cu - 1)
        i = i + 1
      elseif depth_sq == 0 and depth_rd == 0 and depth_cu == 0 then
        local rest = line:sub(i)
        local m_end, arrow, lbl

        -- 1. Arrow with pipe label: -->|label|, -.->|label|, ==>|label|, ---|label|
        local s1, e1, a1, l1 = rest:find("^(<?[%-%.=]+>?[ox]?)%s*|([^|]*)|")
        if s1 and (#a1 >= 2) then
          m_end, arrow, lbl = e1, a1, l1
        end

        -- 2. Inline labeled arrow: -- label -->, -. label .->, == label ==>
        if not m_end then
          local s2, e2, l2, a2 = rest:find("^%-%-%s+([^%-].-)%s+(%-%-+>)")
          if not s2 then
            s2, e2, l2, a2 = rest:find("^%-%s*%.%s*([^%.].-)%s*(%.%-%-+>)")
          end
          if not s2 then
            s2, e2, l2, a2 = rest:find("^%-%s*%.%s*([^%.].-)%s*(%.%->)")
          end
          if not s2 then
            s2, e2, l2, a2 = rest:find("^==%s+([^=].-)%s+(==+>)")
          end
          if s2 then
            m_end, arrow, lbl = e2, a2, l2
          end
        end

        -- 3. Standard unlabeled arrow: -->, -.->, ==>, <--> , ---, etc.
        if not m_end then
          local s3, e3, a3 = rest:find("^(<?[%-%.=]+>[ox]?)")
          if not s3 then
            s3, e3, a3 = rest:find("^([%-%.=][%-%.=][%-%.=]+[ox]?)")
          end
          if s3 then
            m_end, arrow, lbl = e3, a3, ""
          end
        end

        if m_end then
          local node_part = vim.trim(line:sub(seg_start, i - 1))
          if node_part ~= "" then
            table.insert(tokens, { type = "nodes", raw = node_part })
            table.insert(tokens, { type = "edge", arrow = arrow, label = vim.trim(lbl or "") })
          end
          i = i + m_end
          seg_start = i
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end

  local tail = vim.trim(line:sub(seg_start))
  if tail ~= "" then
    table.insert(tokens, { type = "nodes", raw = tail })
  end
  return tokens
end

--- Split `A & B` at bracket/quote depth 0
local function split_ampersand_nodes(raw)
  local parts = {}
  local len = #raw
  local i = 1
  local depth = 0
  local in_quote = nil
  local start_i = 1
  while i <= len do
    local ch = raw:sub(i, i)
    if in_quote then
      if ch == "\\" then
        i = i + 2
      elseif ch == in_quote then
        in_quote = nil
        i = i + 1
      else
        i = i + 1
      end
    else
      if ch == '"' or ch == "'" then
        in_quote = ch
      elseif ch == "[" or ch == "(" or ch == "{" then
        depth = depth + 1
      elseif ch == "]" or ch == ")" or ch == "}" then
        depth = math.max(0, depth - 1)
      elseif ch == "&" and depth == 0 then
        local seg = vim.trim(raw:sub(start_i, i - 1))
        if seg ~= "" then
          table.insert(parts, seg)
        end
        start_i = i + 1
      end
      i = i + 1
    end
  end
  local last = vim.trim(raw:sub(start_i))
  if last ~= "" then
    table.insert(parts, last)
  end
  return parts
end

--- Render a side-by-side row of boxes and return `{ lines = {...}, centers = { col1, col2, ... }, total_width = W }`
local function render_box_row(row_ids, boxes, gap_w, min_center_x)
  local k = #row_ids
  local max_h = 0
  for _, id in ipairs(row_ids) do
    local b = boxes[id]
    if b.height > max_h then
      max_h = b.height
    end
  end

  local col_x = {}
  local centers = {}
  local cur_x = 0
  for idx, id in ipairs(row_ids) do
    local b = boxes[id]
    col_x[idx] = cur_x
    centers[idx] = cur_x + math.floor(b.width / 2)
    cur_x = cur_x + b.width + ((idx < k) and gap_w or 0)
  end
  local row_w = cur_x
  local left_pad = 2
  if min_center_x and k == 1 then
    local desired_left = min_center_x - math.floor(boxes[row_ids[1]].width / 2)
    if desired_left > left_pad then
      left_pad = desired_left
    end
  end

  for idx = 1, k do
    centers[idx] = centers[idx] + left_pad
  end

  local out_lines = {}
  local pad_prefix = string.rep(" ", left_pad)
  for r = 1, max_h do
    local parts = {}
    for idx, id in ipairs(row_ids) do
      local b = boxes[id]
      local top_offset = math.floor((max_h - b.height) / 2)
      local b_row = r - top_offset
      local seg
      if b_row >= 1 and b_row <= b.height then
        seg = b.lines[b_row]
      else
        seg = string.rep(" ", b.width)
      end
      table.insert(parts, pad_str(seg, b.width, "left"))
    end
    local line_str = pad_prefix .. table.concat(parts, string.rep(" ", gap_w))
    table.insert(out_lines, (line_str:gsub("%s+$", "")))
  end

  return {
    lines = out_lines,
    centers = centers,
    total_width = left_pad + row_w,
    center_mid = math.floor((centers[1] + centers[k]) / 2),
  }
end

--- Helper to place characters onto a 1D display column buffer
local function make_canvas_line(width)
  local cells = {}
  for c = 0, width do
    cells[c] = " "
  end
  return {
    cells = cells,
    max_c = width,
    put = function(self, col, str)
      if not col or not str then
        return
      end
      local n_chars = vim.fn.strchars(str)
      local c = math.max(0, math.floor(col))
      for idx = 0, n_chars - 1 do
        local ch = vim.fn.strcharpart(str, idx, 1)
        local cw = math.max(1, str_width(ch))
        self.cells[c] = ch
        for z = 1, cw - 1 do
          self.cells[c + z] = ""
        end
        c = c + cw
      end
      if c > self.max_c then
        self.max_c = c
      end
    end,
    tostring = function(self)
      local out = {}
      for c = 0, self.max_c do
        if self.cells[c] and self.cells[c] ~= "" then
          table.insert(out, self.cells[c])
        end
      end
      return (table.concat(out):gsub("%s+$", ""))
    end,
  }
end

local function render_flowchart(code, opts, custom_title)
  opts = opts or {}
  local max_width = opts.max_width or 88
  local raw_lines = vim.split(code, "\n")
  local nodes = {}
  local edges = {}
  local adj = {}
  local in_deg = {}
  local node_order = {}
  local subgraphs = {} -- list of { id = ..., title = ... }
  local sg_stack = {}
  local node_subgraph = {} -- node_id -> subgraph title

  local is_lr = (code:match("graph%s+LR") or code:match("flowchart%s+LR") or code:match("graph%s+RL") or code:match("flowchart%s+RL")) ~= nil

  local function register_node(id, shape, text)
    if not id or id == "" then
      return
    end
    if not nodes[id] then
      nodes[id] = {
        shape = shape or "rectangle",
        label = (text and text ~= "") and text or id,
        order = #node_order + 1,
      }
      table.insert(node_order, id)
      in_deg[id] = 0
      adj[id] = {}
    else
      if text and text ~= "" and text ~= id then
        nodes[id].label = text
      end
      if shape and shape ~= "" then
        nodes[id].shape = shape
      end
    end
    if #sg_stack > 0 and not node_subgraph[id] then
      node_subgraph[id] = sg_stack[#sg_stack]
    end
  end

  local edge_seen = {}
  local function add_edge(u, v, label, arrow)
    if not u or not v then
      return
    end
    local key = u .. "->" .. v .. ":" .. (label or "")
    if edge_seen[key] then
      return
    end
    edge_seen[key] = true
    table.insert(edges, { from = u, to = v, label = label or "", arrow = arrow or "-->" })
    table.insert(adj[u], { to = v, label = label or "", arrow = arrow or "-->" })
    in_deg[v] = (in_deg[v] or 0) + 1
  end

  for _, raw in ipairs(raw_lines) do
    local line = vim.trim(raw)
    if
      line == ""
      or line:match("^%%")
      or line:match("^graph%s+")
      or line:match("^flowchart%s+")
      or line:match("^style%s+")
      or line:match("^classDef%s+")
      or line:match("^class%s+")
      or line:match("^click%s+")
      or line:match("^linkStyle%s+")
      or line:match("^direction%s+")
    then
      -- skip directives
    elseif line:match("^subgraph%s+") then
      local sg_rest = vim.trim(line:gsub("^subgraph%s+", ""))
      local _, sg_bracket = sg_rest:match("^([%w_%-]+)%s*%[(.*)%]$")
      local sg_title = sg_bracket or sg_rest
      local clean_sg = table.concat(clean_label_lines(sg_title), " ")
      if clean_sg == "" then
        clean_sg = sg_rest
      end
      table.insert(sg_stack, clean_sg)
      table.insert(subgraphs, clean_sg)
    elseif line == "end" then
      if #sg_stack > 0 then
        table.remove(sg_stack)
      end
    else
      local tokens = parse_flowchart_statement(line)
      if #tokens == 1 and tokens[1].type == "nodes" then
        for _, n_expr in ipairs(split_ampersand_nodes(tokens[1].raw)) do
          local id, shape, text = parse_node(n_expr)
          if id then
            register_node(id, shape, text)
          end
        end
      elseif #tokens >= 3 then
        local prev_ids = nil
        local idx = 1
        while idx <= #tokens do
          local tok = tokens[idx]
          if tok.type == "nodes" then
            local cur_ids = {}
            for _, n_expr in ipairs(split_ampersand_nodes(tok.raw)) do
              local id, shape, text = parse_node(n_expr)
              if id then
                register_node(id, shape, text)
                table.insert(cur_ids, id)
              end
            end
            if prev_ids and idx >= 3 and tokens[idx - 1].type == "edge" then
              local e_tok = tokens[idx - 1]
              for _, u in ipairs(prev_ids) do
                for _, v in ipairs(cur_ids) do
                  add_edge(u, v, e_tok.label, e_tok.arrow)
                end
              end
            end
            prev_ids = cur_ids
          end
          idx = idx + 1
        end
      end
    end
  end

  if #node_order == 0 then
    return frame_diagram({ "(Empty or unsupported Mermaid flowchart)" }, custom_title or "󰡷 Mermaid Flowchart", opts)
  end

  -- 1. Identify cycle back-edges via DFS (`visiting` stack) vs true DAG merges
  local dfs_state = {} -- nil, "visiting", "visited"
  local is_back_edge = {} -- "u->v" -> true
  local back_edges_from = {} -- u -> list of { to = v, label = ... }

  local function dfs_cycle(u)
    dfs_state[u] = "visiting"
    for _, e in ipairs(adj[u] or {}) do
      local v = e.to
      if dfs_state[v] == "visiting" then
        is_back_edge[u .. "->" .. v] = true
        back_edges_from[u] = back_edges_from[u] or {}
        table.insert(back_edges_from[u], e)
      elseif not dfs_state[v] then
        dfs_cycle(v)
      end
    end
    dfs_state[u] = "visited"
  end

  for _, id in ipairs(node_order) do
    if not dfs_state[id] then
      dfs_cycle(id)
    end
  end

  -- 2. Compute Longest-Path Topological Layer (`rank[u]`) on the DAG
  local rank = {}
  local dag_parents = {}
  local dag_children = {}
  for _, id in ipairs(node_order) do
    rank[id] = 1
    dag_parents[id] = {}
    dag_children[id] = {}
  end

  for _, e in ipairs(edges) do
    if not is_back_edge[e.from .. "->" .. e.to] and e.from ~= e.to then
      table.insert(dag_children[e.from], e)
      table.insert(dag_parents[e.to], { from = e.from, label = e.label, arrow = e.arrow })
    end
  end

  for _ = 1, #node_order do
    local changed = false
    for _, u in ipairs(node_order) do
      for _, e in ipairs(dag_children[u]) do
        local v = e.to
        if rank[v] < rank[u] + 1 then
          rank[v] = rank[u] + 1
          changed = true
        end
      end
    end
    if not changed then
      break
    end
  end

  local max_rank = 1
  local layers = {}
  for _, id in ipairs(node_order) do
    local r = rank[id]
    if r > max_rank then
      max_rank = r
    end
    layers[r] = layers[r] or {}
    table.insert(layers[r], id)
  end

  -- Sort nodes within each layer by parent barycenter to minimize crossings
  local pos_in_layer = {}
  for r = 1, max_rank do
    local l_nodes = layers[r] or {}
    if r > 1 and #l_nodes > 1 then
      table.sort(l_nodes, function(a, b)
        local function bary(n)
          local ps = dag_parents[n]
          if #ps == 0 then
            return nodes[n].order
          end
          local sum = 0
          for _, p in ipairs(ps) do
            sum = sum + (pos_in_layer[p.from] or nodes[p.from].order)
          end
          return sum / #ps
        end
        local ba, bb = bary(a), bary(b)
        if math.abs(ba - bb) > 0.01 then
          return ba < bb
        end
        return nodes[a].order < nodes[b].order
      end)
    end
    for idx, id in ipairs(l_nodes) do
      pos_in_layer[id] = idx
    end
  end

  -- =========================================================================
  -- SPECIAL MODE: Horizontal Pipeline (`flowchart LR` / `graph LR`)
  -- =========================================================================
  local all_single_layer = true
  for r = 1, max_rank do
    if #(layers[r] or {}) > 1 then
      all_single_layer = false
      break
    end
  end

  if is_lr and all_single_layer and max_rank >= 2 then
    local avail_w = math.max(44, max_width - 4)
    local box_cap = math.max(16, math.min(28, math.floor((avail_w - 10) / math.min(max_rank, 3))))
    local boxes = {}
    for _, id in ipairs(node_order) do
      boxes[id] = make_box(id, nodes[id].shape, nodes[id].label, box_cap)
    end

    -- Group pipeline stages into horizontal rows that fit within `avail_w`
    local h_rows = {}
    local cur_row = {}
    local cur_w = 2
    for r = 1, max_rank do
      local id = layers[r][1]
      local bw = boxes[id].width
      local edge_lbl = ""
      if r < max_rank then
        for _, e in ipairs(dag_children[id]) do
          if e.to == layers[r + 1][1] then
            edge_lbl = e.label or ""
            break
          end
        end
      end
      local arrow_w = (edge_lbl ~= "") and (str_width(edge_lbl) + 6) or 5
      if #cur_row > 0 and (cur_w + bw > avail_w) then
        table.insert(h_rows, cur_row)
        cur_row = { { id = id, edge_lbl = edge_lbl } }
        cur_w = 2 + bw + arrow_w
      else
        table.insert(cur_row, { id = id, edge_lbl = edge_lbl })
        cur_w = cur_w + bw + arrow_w
      end
    end
    if #cur_row > 0 then
      table.insert(h_rows, cur_row)
    end

    local out = {}
    for hr_idx, hr in ipairs(h_rows) do
      local max_h = 0
      for _, item in ipairs(hr) do
        if boxes[item.id].height > max_h then
          max_h = boxes[item.id].height
        end
      end
      local mid_r = math.ceil(max_h / 2)
      local wrap_col = nil
      for r = 1, max_h do
        local line_parts = { "  " }
        for idx, item in ipairs(hr) do
          local b = boxes[item.id]
          local top_off = math.floor((max_h - b.height) / 2)
          local br = r - top_off
          local seg = (br >= 1 and br <= b.height) and b.lines[br] or string.rep(" ", b.width)
          table.insert(line_parts, pad_str(seg, b.width, "left"))
          local is_last_overall = (hr_idx == #h_rows and idx == #hr)
          if not is_last_overall then
            local conn
            if idx < #hr then
              local el = item.edge_lbl
              local arrow_str = (el ~= "") and (" ─[" .. truncate_str(el, 12) .. "]─▶ ") or " ──▶ "
              conn = (r == mid_r) and arrow_str or string.rep(" ", str_width(arrow_str))
            else
              conn = (r == mid_r) and " ──╮" or (r > mid_r and "   │" or "    ")
            end
            table.insert(line_parts, conn)
          end
        end
        local row_str = (table.concat(line_parts):gsub("%s+$", ""))
        if r == mid_r and hr_idx < #h_rows then
          wrap_col = str_width(row_str) - 1
        end
        table.insert(out, row_str)
      end
      if hr_idx < #h_rows then
        local first_next_w = boxes[h_rows[hr_idx + 1][1].id].width
        local target_x = 2 + math.floor(first_next_w / 2)
        local right_x = math.max(target_x + 4, wrap_col or 40)
        table.insert(
          out,
          string.rep(" ", target_x) .. "╭" .. string.rep("─", math.max(1, right_x - target_x - 1)) .. "╯"
        )
        table.insert(out, string.rep(" ", target_x) .. "▼")
      end
    end

    local title = custom_title or "󰡷 Mermaid Flowchart (LR - Live)"
    return frame_diagram(out, title, opts)
  end

  -- =========================================================================
  -- 2D MULTI-COLUMN LAYERED GRAPH RENDERER (`TD` / `TB` & Multi-Branch `LR`)
  -- =========================================================================
  local avail_w = math.max(46, max_width - 6)
  local gap_w = 3

  -- Split any wide layer into visual sub-rows of at most `max_cols_per_row` nodes so boxes stay readable
  local visual_rows = {} -- list of { rank = r, ids = { ... }, subgraph = ... }
  for r = 1, max_rank do
    local l_nodes = layers[r] or {}
    if #l_nodes > 0 then
      local max_cols = 4
      if avail_w < 58 then
        max_cols = 2
      elseif avail_w < 74 then
        max_cols = 3
      elseif avail_w >= 96 then
        max_cols = 5
      end
      for i = 1, #l_nodes, max_cols do
        local chunk = {}
        for j = i, math.min(#l_nodes, i + max_cols - 1) do
          table.insert(chunk, l_nodes[j])
        end
        local sg = node_subgraph[chunk[1]]
        table.insert(visual_rows, { rank = r, ids = chunk, subgraph = sg })
      end
    end
  end

  -- Size each node box according to how many columns share its visual row
  local boxes = {}
  local row_gaps = {}
  for idx, vrow in ipairs(visual_rows) do
    local k = #vrow.ids
    local rg = (k >= 4) and 2 or gap_w
    row_gaps[idx] = rg
    local col_max_w = math.max(15, math.floor((avail_w - (k - 1) * rg) / k))
    for _, id in ipairs(vrow.ids) do
      boxes[id] = make_box(id, nodes[id].shape, nodes[id].label, col_max_w)
    end
  end

  -- Pre-compute rendered rows and align single-node rows with multi-node centers
  local rendered_rows = {}
  local max_row_center = 0
  for idx, vrow in ipairs(visual_rows) do
    local rr = render_box_row(vrow.ids, boxes, row_gaps[idx], nil)
    rendered_rows[idx] = rr
    if #vrow.ids > 1 and rr.center_mid > max_row_center then
      max_row_center = rr.center_mid
    end
  end

  if max_row_center > 0 then
    for idx, vrow in ipairs(visual_rows) do
      if #vrow.ids == 1 then
        rendered_rows[idx] = render_box_row(vrow.ids, boxes, row_gaps[idx], max_row_center)
      end
    end
  end

  local out = {}
  local active_sg = nil

  for v_idx, vrow in ipairs(visual_rows) do
    local rr = rendered_rows[v_idx]

    -- Subgraph header banner when entering a new subgraph
    if vrow.subgraph and vrow.subgraph ~= active_sg then
      active_sg = vrow.subgraph
      local sg_w = math.max(36, math.min(avail_w, rr.total_width))
      local sg_lbl = " 󰉋 " .. active_sg .. " "
      local sg_dashes = string.rep("┈", math.max(6, sg_w - str_width(sg_lbl) - 4))
      table.insert(out, "  ╭┈┈" .. sg_lbl .. sg_dashes .. "╮")
    end

    -- 1. Emit the 2D box row lines
    for _, bl in ipairs(rr.lines) do
      table.insert(out, bl)
    end

    -- 2. Emit any cycle back-edges or cross-layer jump annotations originating from this row
    local next_vrow = visual_rows[v_idx + 1]
    local next_set = {}
    if next_vrow then
      for _, nid in ipairs(next_vrow.ids) do
        next_set[nid] = true
      end
    end

    for c_i, u in ipairs(vrow.ids) do
      -- Back-edges (loops)
      for _, be in ipairs(back_edges_from[u] or {}) do
        local target_lbl = nodes[be.to] and nodes[be.to].label:gsub("\n", " ") or be.to
        local e_lbl = (be.label and be.label ~= "") and (" [" .. be.label .. "]") or ""
        local loop_str = string.format("╰─⟲%s loops to [%s]", e_lbl, truncate_str(target_lbl, 28))
        local c_line = make_canvas_line(rr.total_width)
        c_line:put(math.max(2, rr.centers[c_i] - 2), loop_str)
        table.insert(out, c_line:tostring())
      end

      -- Long-range DAG edges that skip across an intermediate rank (`rank[fe.to] > vrow.rank + 1`)
      if next_vrow then
        for _, fe in ipairs(dag_children[u] or {}) do
          if not next_set[fe.to] and (rank[fe.to] or 0) > vrow.rank + 1 then
            local target_lbl = nodes[fe.to] and nodes[fe.to].label:gsub("\n", " ") or fe.to
            local e_lbl = (fe.label and fe.label ~= "") and (" [" .. fe.label .. "] ──▶ ") or " ──▶ "
            local jump_str = "╰─" .. e_lbl .. "[" .. truncate_str(target_lbl, 26) .. "]"
            local c_line = make_canvas_line(rr.total_width)
            c_line:put(math.max(2, rr.centers[c_i] - 2), jump_str)
            table.insert(out, c_line:tostring())
          end
        end
      end
    end

    -- Close current subgraph before inter-subgraph connectors if next row belongs to a different subgraph
    if active_sg ~= nil and (not next_vrow or next_vrow.subgraph ~= active_sg) then
      local sg_w = math.max(36, math.min(avail_w, rr.total_width))
      table.insert(out, "  ╰" .. string.rep("┈", math.max(24, sg_w - 2)) .. "╯")
      active_sg = nil
    end

    -- 3. Draw 2D connector lines between `vrow` and `next_vrow`
    if next_vrow then
      local next_rr = rendered_rows[v_idx + 1]
      local u_ids = vrow.ids
      local v_ids = next_vrow.ids
      local canvas_w = math.max(rr.total_width, next_rr.total_width) + 16

      -- Collect direct edges from `u_ids` -> `v_ids`
      local row_edges = {}
      local u_has_out = {}
      local v_has_in = {}
      local v_edge_label = {}
      for ui, u in ipairs(u_ids) do
        for _, e in ipairs(dag_children[u] or {}) do
          for vi, v in ipairs(v_ids) do
            if e.to == v then
              table.insert(row_edges, { ui = ui, vi = vi, u = u, v = v, label = e.label or "" })
              u_has_out[ui] = true
              v_has_in[vi] = true
              if e.label and e.label ~= "" then
                v_edge_label[vi] = e.label
              end
            end
          end
        end
      end

      if #row_edges > 0 then
        if #u_ids == 1 and #v_ids == 1 then
          -- Simple 1 -> 1 vertical connection
          local cx = rr.centers[1]
          local tx = next_rr.centers[1]
          local lbl = v_edge_label[1] or ""
          local c1 = make_canvas_line(canvas_w)
          c1:put(cx, "│")
          if lbl ~= "" and cx == tx then
            c1:put(cx + 2, "[" .. truncate_str(lbl, 28) .. "]")
          end
          table.insert(out, c1:tostring())

          if cx ~= tx then
            local bar = make_canvas_line(canvas_w)
            local min_x, max_x = math.min(cx, tx), math.max(cx, tx)
            for x = min_x + 1, max_x - 1 do
              bar:put(x, "─")
            end
            bar:put(cx, (cx < tx) and "╰" or "╯")
            bar:put(tx, (cx < tx) and "╮" or "╭")
            if lbl ~= "" then
              bar:put(max_x + 2, "[" .. truncate_str(lbl, 24) .. "]")
            end
            table.insert(out, bar:tostring())
          end

          local c2 = make_canvas_line(canvas_w)
          c2:put(tx, "▼")
          table.insert(out, c2:tostring())

        elseif #u_ids == 1 and #v_ids > 1 then
          -- 1 -> N Fan-Out Tree Connector (`┌──────┼──────┐`)
          local p_cx = rr.centers[1]
          local active_v = {}
          for vi = 1, #v_ids do
            if v_has_in[vi] then
              table.insert(active_v, vi)
            end
          end
          if #active_v == 0 then
            active_v = { 1 }
          end
          local min_x = p_cx
          local max_x = p_cx
          for _, vi in ipairs(active_v) do
            local cx = next_rr.centers[vi]
            if cx < min_x then min_x = cx end
            if cx > max_x then max_x = cx end
          end

          -- Bar line
          local bar = make_canvas_line(canvas_w)
          for x = min_x, max_x do
            bar:put(x, "─")
          end
          local child_x_set = {}
          for _, vi in ipairs(active_v) do
            child_x_set[next_rr.centers[vi]] = true
          end
          for x = min_x, max_x do
            local is_p = (x == p_cx)
            local is_c = child_x_set[x] == true
            if is_p and is_c then
              bar:put(x, "┼")
            elseif is_p then
              bar:put(x, (x == min_x and "╭") or (x == max_x and "╮") or "┴")
            elseif is_c then
              bar:put(x, (x == min_x and "╭") or (x == max_x and "╮") or "┬")
            end
          end
          table.insert(out, bar:tostring())

          -- Optional edge labels row over each branch column
          local has_any_lbl = false
          for _, vi in ipairs(active_v) do
            if v_edge_label[vi] and v_edge_label[vi] ~= "" then
              has_any_lbl = true
              break
            end
          end
          if has_any_lbl then
            local lbl_line = make_canvas_line(canvas_w)
            for _, vi in ipairs(active_v) do
              local cx = next_rr.centers[vi]
              local el = v_edge_label[vi]
              if el and el ~= "" then
                local tag = "[" .. truncate_str(el, 14) .. "]"
                lbl_line:put(math.max(0, cx - math.floor(str_width(tag) / 2)), tag)
              else
                lbl_line:put(cx, "│")
              end
            end
            table.insert(out, lbl_line:tostring())
          end

          -- Arrowheads row
          local arr = make_canvas_line(canvas_w)
          for _, vi in ipairs(active_v) do
            arr:put(next_rr.centers[vi], "▼")
          end
          table.insert(out, arr:tostring())

        elseif #u_ids > 1 and #v_ids == 1 then
          -- N -> 1 Fan-In Merge Connector (`╰──────┼──────╯` -> `▼`)
          local t_cx = next_rr.centers[1]
          local active_u = {}
          for ui = 1, #u_ids do
            if u_has_out[ui] then
              table.insert(active_u, ui)
            end
          end
          if #active_u == 0 then
            active_u = { 1 }
          end
          local min_x = t_cx
          local max_x = t_cx
          for _, ui in ipairs(active_u) do
            local cx = rr.centers[ui]
            if cx < min_x then min_x = cx end
            if cx > max_x then max_x = cx end
          end

          local bar = make_canvas_line(canvas_w)
          for x = min_x, max_x do
            bar:put(x, "─")
          end
          local parent_x_set = {}
          for _, ui in ipairs(active_u) do
            parent_x_set[rr.centers[ui]] = true
          end
          for x = min_x, max_x do
            local is_u = parent_x_set[x] == true
            local is_t = (x == t_cx)
            if is_u and is_t then
              bar:put(x, "┼")
            elseif is_u then
              bar:put(x, (x == min_x and "╰") or (x == max_x and "╯") or "┴")
            elseif is_t then
              bar:put(x, (x == min_x and "╭") or (x == max_x and "╮") or "┬")
            end
          end
          table.insert(out, bar:tostring())

          local arr = make_canvas_line(canvas_w)
          arr:put(t_cx, "▼")
          local el = v_edge_label[1]
          if el and el ~= "" then
            arr:put(t_cx + 2, "[" .. truncate_str(el, 22) .. "]")
          end
          table.insert(out, arr:tostring())

        else
          -- N -> M Parallel / Multi-Column Connection
          local is_parallel = (#u_ids == #v_ids)
          if is_parallel then
            for _, e in ipairs(row_edges) do
              if e.ui ~= e.vi then
                is_parallel = false
                break
              end
            end
          end

          if is_parallel then
            -- Clean parallel vertical arrows under each column
            local stem = make_canvas_line(canvas_w)
            local arr = make_canvas_line(canvas_w)
            for _, e in ipairs(row_edges) do
              local cx = next_rr.centers[e.vi]
              stem:put(cx, "│")
              if e.label and e.label ~= "" then
                stem:put(cx + 2, "[" .. truncate_str(e.label, 14) .. "]")
              end
              arr:put(cx, "▼")
            end
            table.insert(out, stem:tostring())
            table.insert(out, arr:tostring())
          else
            -- General N -> M bus bar
            local min_x, max_x = 9999, 0
            local u_set, v_set = {}, {}
            for _, e in ipairs(row_edges) do
              local ux = rr.centers[e.ui]
              local vx = next_rr.centers[e.vi]
              u_set[ux] = true
              v_set[vx] = true
              if ux < min_x then min_x = ux end
              if vx < min_x then min_x = vx end
              if ux > max_x then max_x = ux end
              if vx > max_x then max_x = vx end
            end
            local bar = make_canvas_line(canvas_w)
            for x = min_x, max_x do
              bar:put(x, "─")
            end
            for x = min_x, max_x do
              if u_set[x] and v_set[x] then
                bar:put(x, "┼")
              elseif u_set[x] then
                bar:put(x, (x == min_x and "╰") or (x == max_x and "╯") or "┴")
              elseif v_set[x] then
                bar:put(x, (x == min_x and "╭") or (x == max_x and "╮") or "┬")
              end
            end
            table.insert(out, bar:tostring())

            local arr = make_canvas_line(canvas_w)
            for vx, _ in pairs(v_set) do
              arr:put(vx, "▼")
            end
            table.insert(out, arr:tostring())
          end
        end
      else
        -- Visual sub-rows of the same rank or disconnected components: add a subtle vertical gap
        table.insert(out, "")
      end
    end
  end

  if active_sg ~= nil then
    table.insert(out, "  ╰" .. string.rep("┈", math.max(24, math.min(avail_w - 4, 52))) .. "╯")
  end

  local title = custom_title or (is_lr and "󰡷 Mermaid Flowchart (LR - Live)" or "󰡷 Mermaid Flowchart (TD - Live)")
  return frame_diagram(out, title, opts)
end

-- =========================================================================
-- 3. STATE DIAGRAM RENDERER (Uses 2D Layered Flowchart Engine)
-- =========================================================================
local function render_state(code, opts)
  local raw_lines = vim.split(code, "\n")
  local fc_lines = { "flowchart TD" }
  local state_labels = {}
  local end_counter = 0

  for _, raw in ipairs(raw_lines) do
    local line = vim.trim(raw)
    if line == "" or line:match("^%%") or line:match("^stateDiagram") or line:match("^direction%s+") then
      -- skip
    elseif line:match('^state%s+"([^"]+)"%s+as%s+([%w_%-]+)') then
      local lbl, id = line:match('^state%s+"([^"]+)"%s+as%s+([%w_%-]+)')
      state_labels[id] = lbl
      table.insert(fc_lines, string.format('    %s("%s")', id, lbl))
    elseif line:match("^subgraph%s+") or line == "}" or line == "end" then
      if line == "}" then
        table.insert(fc_lines, "    end")
      else
        table.insert(fc_lines, "    " .. line)
      end
    elseif line:match("^state%s+([%w_%-]+)%s*{") then
      local sg_id = line:match("^state%s+([%w_%-]+)%s*{")
      table.insert(fc_lines, "    subgraph " .. (state_labels[sg_id] or sg_id))
    else
      local from, _, to, event = line:match("^([%*_%-%w%[%]]+)%s*([%-%.=]+>)%s*([%*_%-%w%[%]]+)%s*:?%s*(.*)$")
      if from and to then
        local f_node = (from == "[*]") and 'StartNode(("● Start"))' or string.format('%s("%s")', from, state_labels[from] or from)
        local t_node
        if to == "[*]" then
          end_counter = end_counter + 1
          t_node = string.format('EndNode%d(("◉ End"))', end_counter)
        else
          t_node = string.format('%s("%s")', to, state_labels[to] or to)
        end
        local ev = vim.trim(event or "")
        if ev ~= "" then
          table.insert(fc_lines, string.format("    %s -->|%s| %s", f_node, ev, t_node))
        else
          table.insert(fc_lines, string.format("    %s --> %s", f_node, t_node))
        end
      else
        local s_id, desc = line:match("^([%w_%-]+)%s*:%s*(.+)$")
        if s_id and desc then
          state_labels[s_id] = s_id .. "<br/>" .. vim.trim(desc)
          table.insert(fc_lines, string.format('    %s("%s")', s_id, state_labels[s_id]))
        end
      end
    end
  end

  return render_flowchart(table.concat(fc_lines, "\n"), opts, "󰡷 Mermaid State Machine (Live)")
end

-- =========================================================================
-- 4. CLASS DIAGRAM RENDERER
-- =========================================================================
local function render_class(code, opts)
  opts = opts or {}
  local max_width = opts.max_width or 88
  local classes = {}
  local class_order = {}
  local relations = {}
  local cur_class = nil

  local function ensure_class(name)
    name = vim.trim((name or ""):gsub("[`\"~]", ""))
    if name == "" then return nil end
    if not classes[name] then
      classes[name] = { fields = {}, methods = {} }
      table.insert(class_order, name)
    end
    return name
  end

  local function add_member(cname, member)
    member = vim.trim(member)
    if member == "" or member == "{" or member == "}" then return end
    if member:find("%(") then
      table.insert(classes[cname].methods, member)
    else
      table.insert(classes[cname].fields, member)
    end
  end

  for _, raw in ipairs(vim.split(code, "\n")) do
    local line = vim.trim(raw)
    if line == "" or line:match("^%%") or line:match("^classDiagram") or line:match("^direction%s+") then
      -- skip
    elseif cur_class then
      if line == "}" then
        cur_class = nil
      else
        add_member(cur_class, line)
      end
    elseif line:match("^class%s+([%w_%-~]+)%s*{%s*$") then
      cur_class = ensure_class(line:match("^class%s+([%w_%-~]+)%s*{%s*$"))
    elseif line:match("^class%s+([%w_%-~]+)$") then
      ensure_class(line:match("^class%s+([%w_%-~]+)$"))
    else
      local c1, rel, c2, lbl = line:match("^([%w_%-~]+)%s*([<>|%*o%.%-]+)%s*([%w_%-~]+)%s*:?%s*(.*)$")
      if c1 and rel and c2 and (rel:find("%-%-") or rel:find("%.%.") or rel:find("<|") or rel:find("|>")) then
        c1 = ensure_class(c1)
        c2 = ensure_class(c2)
        table.insert(relations, { from = c1, to = c2, rel = rel, label = vim.trim(lbl or "") })
      else
        local cn, mem = line:match("^([%w_%-~]+)%s*:%s*(.+)$")
        if cn and mem then
          cn = ensure_class(cn)
          add_member(cn, mem)
        end
      end
    end
  end

  if #class_order == 0 then
    return frame_diagram({ "(Empty class diagram)" }, "󰡷 Mermaid Class Diagram", opts)
  end

  local boxes = {}
  local avail_w = math.max(44, max_width - 6)
  local cols = math.min(#class_order, avail_w >= 84 and 3 or 2)
  local max_bw = math.max(22, math.floor((avail_w - (cols - 1) * 4) / math.max(1, cols)))

  for _, cname in ipairs(class_order) do
    local info = classes[cname]
    local inner_w = math.max(12, str_width(cname) + 4)
    for _, f in ipairs(info.fields) do
      inner_w = math.max(inner_w, math.min(max_bw - 4, str_width(f) + 2))
    end
    for _, m in ipairs(info.methods) do
      inner_w = math.max(inner_w, math.min(max_bw - 4, str_width(m) + 2))
    end
    local bl = {}
    table.insert(bl, "┌" .. string.rep("─", inner_w + 2) .. "┐")
    table.insert(bl, "│ " .. pad_str(truncate_str(cname, inner_w), inner_w, "center") .. " │")
    if #info.fields > 0 or #info.methods > 0 then
      table.insert(bl, "├" .. string.rep("─", inner_w + 2) .. "┤")
      for _, f in ipairs(info.fields) do
        table.insert(bl, "│ " .. pad_str(truncate_str(f, inner_w), inner_w, "left") .. " │")
      end
      if #info.fields > 0 and #info.methods > 0 then
        table.insert(bl, "├" .. string.rep("┄", inner_w + 2) .. "┤")
      end
      for _, m in ipairs(info.methods) do
        table.insert(bl, "│ " .. pad_str(truncate_str(m, inner_w), inner_w, "left") .. " │")
      end
    end
    table.insert(bl, "└" .. string.rep("─", inner_w + 2) .. "┘")
    boxes[cname] = { lines = bl, height = #bl, width = inner_w + 4 }
  end

  local out = {}
  for i = 1, #class_order, cols do
    local chunk = {}
    for j = i, math.min(#class_order, i + cols - 1) do
      table.insert(chunk, class_order[j])
    end
    local rr = render_box_row(chunk, boxes, 4, nil)
    for _, l in ipairs(rr.lines) do
      table.insert(out, l)
    end
    table.insert(out, "")
  end

  if #relations > 0 then
    table.insert(out, "  Relationships:")
    for _, r in ipairs(relations) do
      local lbl = (r.label ~= "") and (" : " .. r.label) or ""
      table.insert(out, string.format("    [%s] %s [%s]%s", r.from, r.rel, r.to, lbl))
    end
  end

  return frame_diagram(out, "󰡷 Mermaid Class Diagram (Live)", opts)
end

-- =========================================================================
-- 5. ENTITY-RELATIONSHIP (ER) DIAGRAM RENDERER
-- =========================================================================
local function render_er(code, opts)
  opts = opts or {}
  local max_width = opts.max_width or 88
  local entities = {}
  local entity_order = {}
  local rels = {}
  local cur_ent = nil

  local function ensure_entity(name)
    name = vim.trim((name or ""):gsub('"', ""))
    if name == "" then return nil end
    if not entities[name] then
      entities[name] = { attrs = {} }
      table.insert(entity_order, name)
    end
    return name
  end

  for _, raw in ipairs(vim.split(code, "\n")) do
    local line = vim.trim(raw)
    if line == "" or line:match("^%%") or line:match("^erDiagram") then
      -- skip
    elseif cur_ent then
      if line == "}" then
        cur_ent = nil
      else
        table.insert(entities[cur_ent].attrs, line)
      end
    elseif line:match("^([%w_%-\"]+)%s*{%s*$") then
      cur_ent = ensure_entity(line:match("^([%w_%-\"]+)%s*{%s*$"))
    else
      local e1, card, e2, lbl = line:match("^([%w_%-\"]+)%s+([|o}{%.%-]+)%s+([%w_%-\"]+)%s*:%s*(.+)$")
      if e1 and card and e2 then
        e1 = ensure_entity(e1)
        e2 = ensure_entity(e2)
        local clean_l = vim.trim(lbl or ""):gsub('^"(.*)"$', "%1")
        table.insert(rels, { from = e1, to = e2, card = card, label = clean_l })
      end
    end
  end

  if #entity_order == 0 then
    return frame_diagram({ "(Empty ER diagram)" }, "󰡷 Mermaid ER Diagram", opts)
  end

  local boxes = {}
  local avail_w = math.max(44, max_width - 6)
  local cols = math.min(#entity_order, avail_w >= 84 and 3 or 2)
  local max_bw = math.max(22, math.floor((avail_w - (cols - 1) * 4) / math.max(1, cols)))

  for _, ename in ipairs(entity_order) do
    local info = entities[ename]
    local inner_w = math.max(12, str_width(ename) + 4)
    for _, a in ipairs(info.attrs) do
      inner_w = math.max(inner_w, math.min(max_bw - 4, str_width(a) + 2))
    end
    local bl = {
      "┌" .. string.rep("─", inner_w + 2) .. "┐",
      "│ " .. pad_str(truncate_str(ename, inner_w), inner_w, "center") .. " │",
    }
    if #info.attrs > 0 then
      table.insert(bl, "├" .. string.rep("─", inner_w + 2) .. "┤")
      for _, a in ipairs(info.attrs) do
        table.insert(bl, "│ " .. pad_str(truncate_str(a, inner_w), inner_w, "left") .. " │")
      end
    end
    table.insert(bl, "└" .. string.rep("─", inner_w + 2) .. "┘")
    boxes[ename] = { lines = bl, height = #bl, width = inner_w + 4 }
  end

  local out = {}
  for i = 1, #entity_order, cols do
    local chunk = {}
    for j = i, math.min(#entity_order, i + cols - 1) do
      table.insert(chunk, entity_order[j])
    end
    local rr = render_box_row(chunk, boxes, 4, nil)
    for _, l in ipairs(rr.lines) do
      table.insert(out, l)
    end
    table.insert(out, "")
  end

  if #rels > 0 then
    table.insert(out, "  Cardinality & Relationships:")
    for _, r in ipairs(rels) do
      table.insert(out, string.format("    [%s]  %s  [%s]  : %s", r.from, r.card, r.to, r.label))
    end
  end

  return frame_diagram(out, "󰡷 Mermaid ER Diagram (Live)", opts)
end

-- =========================================================================
-- 6. PIE CHART RENDERER
-- =========================================================================
local function render_pie(code, opts)
  opts = opts or {}
  local title = "󰡷 Mermaid Pie Chart (Live)"
  local items = {}
  local total = 0

  for _, raw in ipairs(vim.split(code, "\n")) do
    local line = vim.trim(raw)
    local t_inline = line:match("^pie%s+title%s+(.+)$") or line:match("^title%s+(.+)$")
    if t_inline then
      title = "󰡷 " .. vim.trim(t_inline)
    else
      local lbl, val = line:match('^"([^"]+)"%s*:%s*([%d%.]+)$')
      if lbl and val then
        local v = tonumber(val) or 0
        total = total + v
        table.insert(items, { label = lbl, value = v })
      end
    end
  end

  if #items == 0 then
    return frame_diagram({ "(Empty pie chart)" }, title, opts)
  end

  local out = {}
  local bar_w = 24
  for _, it in ipairs(items) do
    local pct = (total > 0) and ((it.value / total) * 100) or 0
    local filled = math.max(0, math.min(bar_w, math.floor((pct / 100) * bar_w + 0.5)))
    local bar = string.rep("█", filled) .. string.rep("░", bar_w - filled)
    table.insert(out, string.format("  %s  %5.1f%%  %s (%s)", bar, pct, it.label, tostring(it.value)))
  end

  return frame_diagram(out, title, opts)
end

-- =========================================================================
-- 7. MULTI-COLOR LINE TOKENIZER FOR IN-BUFFER & POPUP RENDERING
-- =========================================================================
function M.tokenize_line(line)
  local chunks = {}
  local len = #line
  local i = 1
  while i <= len do
    local b3 = line:sub(i, i + 2)
    if
      b3 == "┌" or b3 == "─" or b3 == "┬" or b3 == "┐"
      or b3 == "│" or b3 == "├" or b3 == "┼" or b3 == "┤"
      or b3 == "└" or b3 == "┴" or b3 == "┘"
      or b3 == "╭" or b3 == "╮" or b3 == "╰" or b3 == "╯"
      or b3 == "╔" or b3 == "═" or b3 == "╗" or b3 == "║" or b3 == "╚" or b3 == "╝"
      or b3 == "◇" or b3 == "╱" or b3 == "╲" or b3 == "┈" or b3 == "┄"
    then
      local s = i
      while i <= len do
        local nb3 = line:sub(i, i + 2)
        if
          nb3 == "┌" or nb3 == "─" or nb3 == "┬" or nb3 == "┐"
          or nb3 == "│" or nb3 == "├" or nb3 == "┼" or nb3 == "┤"
          or nb3 == "└" or nb3 == "┴" or nb3 == "┘"
          or nb3 == "╭" or nb3 == "╮" or nb3 == "╰" or nb3 == "╯"
          or nb3 == "╔" or nb3 == "═" or nb3 == "╗" or nb3 == "║" or nb3 == "╚" or nb3 == "╝"
          or nb3 == "◇" or nb3 == "╱" or nb3 == "╲" or nb3 == "┈" or nb3 == "┄"
        then
          i = i + 3
        else
          break
        end
      end
      table.insert(chunks, { line:sub(s, i - 1), "SuperMarkdownMermaidType" })
    elseif b3 == "▶" or b3 == "◀" or b3 == "▲" or b3 == "▼" or b3 == "●" or b3 == "◉" or b3 == "⟲" or b3 == "╌" then
      table.insert(chunks, { b3, "SuperMarkdownMermaidArrow" })
      i = i + 3
    else
      local ch = line:sub(i, i)
      if ch == "[" then
        local c_e = line:find("%]", i + 1)
        if c_e then
          table.insert(chunks, { line:sub(i, c_e), "SuperMarkdownMermaidEdgeLabel" })
          i = c_e + 1
        else
          table.insert(chunks, { ch, "SuperMarkdownMermaidNodeLabel" })
          i = i + 1
        end
      else
        local s = i
        while i <= len do
          local nb3 = line:sub(i, i + 2)
          local nch = line:sub(i, i)
          if
            nb3 == "┌" or nb3 == "─" or nb3 == "┬" or nb3 == "┐"
            or nb3 == "│" or nb3 == "├" or nb3 == "┼" or nb3 == "┤"
            or nb3 == "└" or nb3 == "┴" or nb3 == "┘"
            or nb3 == "╭" or nb3 == "╮" or nb3 == "╰" or nb3 == "╯"
            or nb3 == "╔" or nb3 == "═" or nb3 == "╗" or nb3 == "║" or nb3 == "╚" or nb3 == "╝"
            or nb3 == "◇" or nb3 == "╱" or nb3 == "╲" or nb3 == "┈" or nb3 == "┄"
            or nb3 == "▶" or nb3 == "◀" or nb3 == "▲" or nb3 == "▼" or nb3 == "●" or nb3 == "◉" or nb3 == "⟲" or nb3 == "╌"
            or nch == "["
          then
            break
          end
          i = i + 1
        end
        table.insert(chunks, { line:sub(s, i - 1), "SuperMarkdownMermaidNodeLabel" })
      end
    end
  end
  return chunks
end

-- =========================================================================
-- MAIN RENDER DISPATCHER
-- =========================================================================
function M.render(mermaid_code, opts)
  local trimmed = vim.trim(mermaid_code or "")
  -- Strip leading `%%{init: ...}%%` directives if present
  trimmed = vim.trim(trimmed:gsub("^%%%%%b{}%%%%%s*", ""))

  if trimmed:match("^sequenceDiagram") then
    return render_sequence(trimmed, opts)
  elseif trimmed:match("^stateDiagram") then
    return render_state(trimmed, opts)
  elseif trimmed:match("^classDiagram") then
    return render_class(trimmed, opts)
  elseif trimmed:match("^erDiagram") then
    return render_er(trimmed, opts)
  elseif trimmed:match("^pie") then
    return render_pie(trimmed, opts)
  else
    return render_flowchart(trimmed, opts)
  end
end

return M
