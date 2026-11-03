local M = {}

local function str_width(s)
  return vim.fn.strdisplaywidth(s)
end

local function pad_str(s, width, align)
  local len = str_width(s)
  if len >= width then return s end
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

--- Parse a node string like `A[Start]`, `B{Choice?}`, `C[(Database)]`, etc.
local function parse_node(str)
  if not str or str == "" then return nil end
  str = str:gsub("<br%s*/?>", " / ")
  local id, shape, text

  -- Database: [(text)]
  id, text = str:match("([%w_%-]+)%s*%[%((.-)%)%]")
  if id and text then return id, "database", vim.trim(text) end

  -- Stadium: ([text])
  id, text = str:match("([%w_%-]+)%s*%(%[(.-)%]%)")
  if id and text then return id, "stadium", vim.trim(text) end

  -- Circle: ((text))
  id, text = str:match("([%w_%-]+)%s*%(%((.-)%)%)")
  if id and text then return id, "circle", vim.trim(text) end

  -- Decision: {text}
  id, text = str:match("([%w_%-]+)%s*%{(.-)%}")
  if id and text then return id, "decision", vim.trim(text) end

  -- Rounded: (text)
  id, text = str:match("([%w_%-]+)%s*%((.-)%)")
  if id and text then return id, "rounded", vim.trim(text) end

  -- Rectangle: [text]
  id, text = str:match("([%w_%-]+)%s*%[(.-)%]")
  if id and text then return id, "rectangle", vim.trim(text) end

  -- Just an ID
  id = str:match("([%w_%-]+)")
  if id then return id, "rectangle", id end

  return nil
end

local function truncate_str(s, max_w)
  if str_width(s) <= max_w then return s end
  if max_w <= 1 then return "…" end
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

--- Render a single node box
local function make_box(id, shape, text, max_box_w)
  local label = (text and text ~= "") and text or id
  if max_box_w and max_box_w > 6 then
    label = truncate_str(label, max_box_w - 4)
  end
  local w = str_width(label) + 2
  local top, mid, bot

  if shape == "database" then
    top = "[(" .. string.rep("─", w) .. ")]"
    mid = "│ " .. label .. " │"
    bot = "[(" .. string.rep("─", w) .. ")]"
  elseif shape == "decision" then
    top = "◇─" .. string.rep("─", math.max(0, w - 2)) .. "─◇"
    mid = "│ " .. label .. " │"
    bot = "◇─" .. string.rep("─", math.max(0, w - 2)) .. "─◇"
  elseif shape == "rounded" or shape == "stadium" then
    top = "╭─" .. string.rep("─", math.max(0, w - 2)) .. "─╮"
    mid = "│ " .. label .. " │"
    bot = "╰─" .. string.rep("─", math.max(0, w - 2)) .. "─╯"
  elseif shape == "circle" then
    top = "(( " .. label .. " ))"
    mid = nil
    bot = nil
  else
    top = "┌─" .. string.rep("─", math.max(0, w - 2)) .. "─┐"
    mid = "│ " .. label .. " │"
    bot = "└─" .. string.rep("─", math.max(0, w - 2)) .. "─┘"
  end

  return {
    top = top,
    mid = mid or top,
    bot = bot or top,
    width = str_width(top),
    label = label,
  }
end

--- Frame lines inside a nice Unicode border card
local function frame_diagram(lines, title, opts)
  opts = opts or {}
  if opts.bare then
    return lines
  end
  local max_w = str_width(title) + 6
  for _, l in ipairs(lines) do
    local w = str_width(l)
    if w > max_w then max_w = w end
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

  for _, raw_line in ipairs(lines) do
    local line = vim.trim(raw_line)
    if line:match("^autonumber") then
      autonumber = true
    elseif line:match("^actor%s+") or line:match("^participant%s+") then
      local p_type = line:match("^(%w+)")
      local rest = line:gsub("^%w+%s+", "")
      local id, as_name = rest:match("([%w_%-]+)%s+as%s+(.+)")
      if not id then
        id = rest:match("([%w_%-]+)")
        as_name = id
      end
      if id and not p_lookup[id] then
        local entry = { id = id, name = vim.trim(as_name or id), type = p_type }
        table.insert(participants, entry)
        p_lookup[id] = #participants
      end
    else
      local from_id, arrow, to_id, text = line:match("([%a_][%w_]*)%s*([%-%.=]+>>?)%s*([%a_][%w_]*)%s*:%s*(.+)")
      if from_id and to_id and text then
        if not p_lookup[from_id] then
          table.insert(participants, { id = from_id, name = from_id, type = "participant" })
          p_lookup[from_id] = #participants
        end
        if not p_lookup[to_id] then
          table.insert(participants, { id = to_id, name = to_id, type = "participant" })
          p_lookup[to_id] = #participants
        end
        step = step + 1
        table.insert(messages, {
          from = from_id,
          to = to_id,
          arrow = arrow,
          text = vim.trim(text),
          step = autonumber and step or nil,
        })
      elseif line:match("^alt%s+") or line:match("^else") or line:match("^end") or line:match("^opt%s+") then
        table.insert(messages, { note = line })
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
    col_widths[i] = math.max(str_width(p.name) + 4, 14)
    disp_names[i] = p.name
  end

  -- Ensure adjacent columns have enough span for message labels, while respecting max_width on resize
  for _, m in ipairs(messages) do
    if not m.note then
      local f_i = p_lookup[m.from]
      local t_i = p_lookup[m.to]
      if f_i and t_i and f_i ~= t_i and math.abs(t_i - f_i) == 1 then
        local min_i = math.min(f_i, t_i)
        local lbl_w = str_width((m.step and (m.step .. ". ") or "") .. m.text) + 4
        local cur_span = math.floor(col_widths[min_i] / 2) + gap_w + math.floor(col_widths[min_i + 1] / 2)
        if lbl_w > cur_span then
          local extra = math.min(12, lbl_w - cur_span)
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
      for i, p in ipairs(participants) do
        col_widths[i] = math.min(col_widths[i], base_w)
        disp_names[i] = truncate_str(p.name, math.max(4, col_widths[i] - 2))
      end
    end
  end

  local col_gap = string.rep(" ", gap_w)

  -- Compute exact character column center for each participant's lifeline
  local centers = {}
  local offset = 0
  for i = 1, n_p do
    local half = math.floor(col_widths[i] / 2)
    centers[i] = offset + half -- 0-indexed display column of lifeline
    offset = offset + col_widths[i] + ((i < n_p) and gap_w or 0)
  end
  local total_grid_w = offset

  -- Helper to render a line on the exact lifeline grid with optional text or arrow overlay
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

  -- Build participant header/footer boxes
  local h_top_parts = {}
  local h_mid_parts = {}
  local h_bot_parts = {}

  for i = 1, n_p do
    local w = col_widths[i]
    table.insert(h_top_parts, "┌" .. string.rep("─", w - 2) .. "┐")
    table.insert(h_mid_parts, "│" .. pad_str(disp_names[i], w - 2, "center") .. "│")
    table.insert(h_bot_parts, "└" .. string.rep("─", w - 2) .. "┘")
  end

  local h_top = table.concat(h_top_parts, col_gap)
  local h_mid = table.concat(h_mid_parts, col_gap)
  local h_bot = table.concat(h_bot_parts, col_gap)

  local out = {}
  table.insert(out, h_top)
  table.insert(out, h_mid)
  table.insert(out, h_bot)
  table.insert(out, render_grid_row())

  for _, m in ipairs(messages) do
    if m.note then
      local note_str = "[ " .. m.note .. " ]"
      if max_width and max_width > 12 then
        note_str = truncate_str(note_str, max_width - 4)
      end
      table.insert(out, render_grid_row(math.max(0, centers[1] - 1), note_str))
      table.insert(out, render_grid_row())
    else
      local from_idx = p_lookup[m.from]
      local to_idx = p_lookup[m.to]
      local label = (m.step and (m.step .. ". ") or "") .. m.text

      if from_idx == to_idx then
        local c_pos = centers[from_idx]
        local avail_lbl
        if from_idx < n_p then
          avail_lbl = math.max(6, centers[from_idx + 1] - c_pos - 6)
        else
          avail_lbl = max_width and math.max(8, max_width - c_pos - 6) or 36
        end
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

        local clean_lbl = truncate_str(label, math.max(6, span_w - 2))
        local lbl_col = c_left + 1 + math.max(0, math.floor((span_w - str_width(clean_lbl)) / 2))
        table.insert(out, render_grid_row(lbl_col, clean_lbl))

        local is_dashed = m.arrow:find("%-%.") ~= nil or m.arrow:find("%-%-") ~= nil
        local dash_unit = is_dashed and "╌" or "─"
        local shaft = string.rep(dash_unit, math.max(1, span_w - 1))
        local arr_overlay
        if ltr then
          arr_overlay = "├" .. shaft .. "▶│"
        else
          arr_overlay = "│◀" .. shaft .. "┤"
        end
        table.insert(out, render_grid_row(c_left, arr_overlay))
      end

      table.insert(out, render_grid_row())
    end
  end

  table.insert(out, h_top)
  table.insert(out, h_mid)
  table.insert(out, h_bot)

  return frame_diagram(out, "󰡷 Mermaid Sequence Diagram (Live)", opts)
end

-- =========================================================================
-- 2. STATE DIAGRAM RENDERER
-- =========================================================================
local function render_state(code, opts)
  opts = opts or {}
  local max_box_w = opts.max_width and math.max(16, opts.max_width - 8) or nil
  local raw_lines = vim.split(code, "\n")
  local states = {}
  local state_order = {}
  local transitions = {}

  for _, raw in ipairs(raw_lines) do
    local line = vim.trim(raw)
    if not (line == "" or line:match("^stateDiagram")) then
      local from, arrow, to, event = line:match("([%*_%-%w%[%]]+)%s*([%-%.=]+>)%s*([%*_%-%w%[%]]+)%s*:?%s*(.*)")
      if from and to then
        local clean_event = vim.trim(event or "")
        table.insert(transitions, { from = from, to = to, event = clean_event })
        if from ~= "[*]" and not states[from] then
          states[from] = true
          table.insert(state_order, from)
        end
        if to ~= "[*]" and not states[to] then
          states[to] = true
          table.insert(state_order, to)
        end
      end
    end
  end

  local out = {}
  table.insert(out, "  ● [Start]")

  for _, t in ipairs(transitions) do
    local ev_txt = t.event or ""
    if max_box_w and ev_txt ~= "" then
      ev_txt = truncate_str(ev_txt, math.max(8, max_box_w - 10))
    end
    local lbl = (ev_txt ~= "") and ("  [" .. ev_txt .. "]") or ""
    table.insert(out, "      │" .. lbl)
    table.insert(out, "      ▼")
    if t.to == "[*]" then
      table.insert(out, "    ◉ [End]")
    else
      local s_box = make_box(t.to, "rounded", t.to, max_box_w)
      table.insert(out, "  " .. s_box.top)
      table.insert(out, "  " .. s_box.mid)
      table.insert(out, "  " .. s_box.bot)
    end
  end

  return frame_diagram(out, "󰡷 Mermaid State Machine (Live)", opts)
end

-- =========================================================================
-- 3. FLOWCHART / GRAPH RENDERER
-- =========================================================================
local function render_flowchart(code, opts)
  opts = opts or {}
  local max_width = opts.max_width
  local max_box_w = max_width and math.max(18, max_width - 8) or nil
  local raw_lines = vim.split(code, "\n")
  local nodes = {}
  local edges = {}
  local adj = {}
  local in_deg = {}
  local node_order = {}

  local is_lr = code:match("graph%s+LR") or code:match("flowchart%s+LR")

  local function register_node(id, shape, text)
    if not id or id == "" then return end
    if not nodes[id] then
      nodes[id] = { shape = shape or "rectangle", label = text or id }
      table.insert(node_order, id)
      in_deg[id] = 0
      adj[id] = {}
    elseif text and text ~= id then
      nodes[id].label = text
      if shape and shape ~= "rectangle" then
        nodes[id].shape = shape
      end
    end
  end

  for _, raw in ipairs(raw_lines) do
    local line = vim.trim(raw)
    if not (
      line == ""
      or line:match("^%%")
      or line:match("^graph%s+")
      or line:match("^flowchart%s+")
      or line:match("^subgraph%s+")
      or line == "end"
      or line:match("^style%s+")
      or line:match("^classDef%s+")
      or line:match("^class%s+")
      or line:match("^click%s+")
      or line:match("^direction%s+")
    ) then
      local left, arrow, label, right
      left, arrow, label, right = line:match("^(.-)%s*([%-%.=]+>)%s*|([^|]+)|%s*(.+)$")
      if not left then
        left, label, right = line:match("^(.-)%s*%-%-%s*(.-)%s*%-%->%s*(.+)$")
        arrow = "-->"
      end
      if not left then
        left, arrow, right = line:match("^(.-)%s*([%-%.=]+>)%s*(.+)$")
        label = ""
      end

      if left and arrow and right then
        local l_id, l_shape, l_text = parse_node(left)
        local r_id, r_shape, r_text = parse_node(right)

        if l_id and r_id then
          register_node(l_id, l_shape, l_text)
          register_node(r_id, r_shape, r_text)
          table.insert(edges, { from = l_id, to = r_id, label = vim.trim(label or ""), arrow = arrow })
          table.insert(adj[l_id], { to = r_id, label = vim.trim(label or "") })
          in_deg[r_id] = (in_deg[r_id] or 0) + 1
        end
      else
        local s_id, s_shape, s_text = parse_node(line)
        if s_id then
          register_node(s_id, s_shape, s_text)
        end
      end
    end
  end

  if #node_order == 0 then
    return frame_diagram({ "(Empty or unsupported Mermaid flowchart)" }, "󰡷 Mermaid Flowchart", opts)
  end

  local boxes = {}
  for id, info in pairs(nodes) do
    boxes[id] = make_box(id, info.shape, info.label, max_box_w)
  end

  local out = {}
  local roots = {}
  for _, id in ipairs(node_order) do
    if (in_deg[id] or 0) == 0 then
      table.insert(roots, id)
    end
  end
  if #roots == 0 then
    table.insert(roots, node_order[1])
  end

  local visited = {}

  local function draw_subgraph(u, indent)
    indent = indent or ""
    if visited[u] then
      local loop_lbl = nodes[u] and nodes[u].label or u
      if max_box_w then
        loop_lbl = truncate_str(loop_lbl, math.max(8, max_box_w - 18))
      end
      table.insert(out, indent .. "└─ ⟲ (loops to [" .. loop_lbl .. "])")
      return
    end
    visited[u] = true

    local b = boxes[u]
    table.insert(out, indent .. b.top)
    table.insert(out, indent .. b.mid)
    table.insert(out, indent .. b.bot)

    local children = adj[u] or {}
    if #children == 0 then
      return
    elseif #children == 1 then
      local child = children[1]
      local c_lbl = child.label or ""
      if max_box_w and c_lbl ~= "" then
        c_lbl = truncate_str(c_lbl, math.max(8, max_box_w - 12))
      end
      local lbl = (c_lbl ~= "") and ("  [" .. c_lbl .. "]") or ""
      table.insert(out, indent .. "      │" .. lbl)
      table.insert(out, indent .. "      ▼")
      draw_subgraph(child.to, indent)
    else
      for i, child in ipairs(children) do
        local is_last = (i == #children)
        local branch_char = is_last and "└" or "├"
        local c_lbl = child.label or ""
        local target_lbl = nodes[child.to] and nodes[child.to].label or child.to
        if max_box_w then
          c_lbl = truncate_str(c_lbl, math.max(6, math.floor(max_box_w / 3)))
          target_lbl = truncate_str(target_lbl, math.max(8, math.floor(max_box_w / 2)))
        end
        local lbl = (c_lbl ~= "") and (" [" .. c_lbl .. "] ──▶ ") or " ──▶ "
        table.insert(out, indent .. "      " .. branch_char .. "────" .. lbl .. "[" .. target_lbl .. "]")
      end
      -- Continue traversing down each child
      for _, child in ipairs(children) do
        if not visited[child.to] then
          table.insert(out, indent .. "      │")
          table.insert(out, indent .. "      ▼")
          draw_subgraph(child.to, indent)
        end
      end
    end
  end

  for _, root in ipairs(roots) do
    draw_subgraph(root, "  ")
    table.insert(out, "")
  end

  for _, id in ipairs(node_order) do
    if not visited[id] then
      draw_subgraph(id, "  ")
      table.insert(out, "")
    end
  end

  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end

  local title = is_lr and "󰡷 Mermaid Flowchart (LR - Live)" or "󰡷 Mermaid Flowchart (TD - Live)"
  return frame_diagram(out, title, opts)
end

-- =========================================================================
-- MAIN RENDER DISPATCHER
-- =========================================================================
function M.render(mermaid_code, opts)
  local trimmed = vim.trim(mermaid_code)
  if trimmed:match("^sequenceDiagram") then
    return render_sequence(trimmed, opts)
  elseif trimmed:match("^stateDiagram") then
    return render_state(trimmed, opts)
  else
    return render_flowchart(trimmed, opts)
  end
end

return M
