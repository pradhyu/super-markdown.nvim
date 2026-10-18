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

--- Render a single node box
local function make_box(id, shape, text)
  local label = (text and text ~= "") and text or id
  local w = str_width(label) + 2
  local top, mid, bot

  if shape == "database" then
    top = "[(" .. string.rep("─", w) .. ")]"
    mid = "│ " .. label .. " │"
    bot = "[(" .. string.rep("─", w) .. ")]"
  elseif shape == "decision" then
    top = "◇─" .. string.rep("─", w - 2) .. "─◇"
    mid = "│ " .. label .. " │"
    bot = "◇─" .. string.rep("─", w - 2) .. "─◇"
  elseif shape == "rounded" or shape == "stadium" then
    top = "╭─" .. string.rep("─", w - 2) .. "─╮"
    mid = "│ " .. label .. " │"
    bot = "╰─" .. string.rep("─", w - 2) .. "─╯"
  elseif shape == "circle" then
    top = "(( " .. label .. " ))"
    mid = nil
    bot = nil
  else
    top = "┌─" .. string.rep("─", w - 2) .. "─┐"
    mid = "│ " .. label .. " │"
    bot = "└─" .. string.rep("─", w - 2) .. "─┘"
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
local function frame_diagram(lines, title)
  local max_w = str_width(title) + 6
  for _, l in ipairs(lines) do
    local w = str_width(l)
    if w > max_w then max_w = w end
  end
  max_w = math.max(max_w + 4, 52)

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
local function render_sequence(code)
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
    return frame_diagram({ "(Empty sequence diagram)" }, "󰡷 Mermaid Sequence Diagram")
  end

  -- Compute column widths
  local col_widths = {}
  for i, p in ipairs(participants) do
    local w = math.max(str_width(p.name) + 4, 16)
    col_widths[i] = w
  end

  -- Build participant boxes
  local h_top_parts = {}
  local h_mid_parts = {}
  local h_bot_parts = {}

  for i, p in ipairs(participants) do
    local w = col_widths[i]
    table.insert(h_top_parts, "┌" .. string.rep("─", w - 2) .. "┐")
    table.insert(h_mid_parts, "│" .. pad_str(p.name, w - 2, "center") .. "│")
    table.insert(h_bot_parts, "└" .. string.rep("─", w - 2) .. "┘")
  end

  local col_gap = "     "
  local h_top = table.concat(h_top_parts, col_gap)
  local h_mid = table.concat(h_mid_parts, col_gap)
  local h_bot = table.concat(h_bot_parts, col_gap)

  local function make_lifeline()
    local parts = {}
    for i, w in ipairs(col_widths) do
      local half = math.floor(w / 2)
      local rest = w - half - 1
      table.insert(parts, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
    end
    return table.concat(parts, col_gap)
  end

  local out = {}
  table.insert(out, h_top)
  table.insert(out, h_mid)
  table.insert(out, h_bot)
  table.insert(out, make_lifeline())

  for _, m in ipairs(messages) do
    if m.note then
      table.insert(out, "  " .. m.note)
      table.insert(out, make_lifeline())
    else
      local from_idx = p_lookup[m.from]
      local to_idx = p_lookup[m.to]
      local label = (m.step and (m.step .. ". ") or "") .. m.text

      if from_idx == to_idx then
        -- Self call
        local parts = {}
        for i, w in ipairs(col_widths) do
          local half = math.floor(w / 2)
          local rest = w - half - 1
          if i == from_idx then
            table.insert(parts, string.rep(" ", half) .. "│ ──╮" .. string.rep(" ", math.max(0, rest - 4)))
          else
            table.insert(parts, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
          end
        end
        table.insert(out, table.concat(parts, col_gap))

        local parts_text = {}
        for i, w in ipairs(col_widths) do
          local half = math.floor(w / 2)
          local rest = w - half - 1
          if i == from_idx then
            table.insert(parts_text, string.rep(" ", half) .. "│ " .. label .. string.rep(" ", rest))
          else
            table.insert(parts_text, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
          end
        end
        table.insert(out, table.concat(parts_text, col_gap))

        local parts_ret = {}
        for i, w in ipairs(col_widths) do
          local half = math.floor(w / 2)
          local rest = w - half - 1
          if i == from_idx then
            table.insert(parts_ret, string.rep(" ", half) .. "│ ◀─╯" .. string.rep(" ", math.max(0, rest - 4)))
          else
            table.insert(parts_ret, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
          end
        end
        table.insert(out, table.concat(parts_ret, col_gap))
      else
        local min_idx = math.min(from_idx, to_idx)
        local max_idx = math.max(from_idx, to_idx)
        local ltr = (from_idx < to_idx)

        -- Text label line above arrow
        local parts_lbl = {}
        for i, w in ipairs(col_widths) do
          local half = math.floor(w / 2)
          local rest = w - half - 1
          if i == min_idx then
            table.insert(parts_lbl, string.rep(" ", half) .. "│ " .. label)
          elseif i > min_idx and i <= max_idx then
            table.insert(parts_lbl, "")
          else
            table.insert(parts_lbl, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
          end
        end
        table.insert(out, table.concat(parts_lbl, col_gap))

        -- Arrow line with precise gap filling
        local parts_arr = {}
        for i, w in ipairs(col_widths) do
          local half = math.floor(w / 2)
          local rest = w - half - 1
          if i < min_idx or i > max_idx then
            table.insert(parts_arr, string.rep(" ", half) .. "│" .. string.rep(" ", rest))
          elseif i == min_idx then
            local pre = string.rep(" ", half) .. (ltr and "│" or "◀")
            local post = string.rep("─", rest)
            table.insert(parts_arr, pre .. post)
          elseif i == max_idx then
            local pre = string.rep("─", half) .. (ltr and "▶" or "│")
            local post = string.rep(" ", rest)
            table.insert(parts_arr, pre .. post)
          else
            table.insert(parts_arr, string.rep("─", w))
          end
        end

        local arr_str = ""
        for i, p in ipairs(parts_arr) do
          arr_str = arr_str .. p
          if i < #parts_arr then
            if i >= min_idx and i < max_idx then
              arr_str = arr_str .. string.rep("─", #col_gap)
            else
              arr_str = arr_str .. string.rep(" ", #col_gap)
            end
          end
        end
        table.insert(out, arr_str)
      end

      table.insert(out, make_lifeline())
    end
  end

  table.insert(out, h_top)
  table.insert(out, h_mid)
  table.insert(out, h_bot)

  return frame_diagram(out, "󰡷 Mermaid Sequence Diagram (Live)")
end

-- =========================================================================
-- 2. STATE DIAGRAM RENDERER
-- =========================================================================
local function render_state(code)
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

  local visited = {}
  for _, t in ipairs(transitions) do
    local lbl = (t.event ~= "") and ("  [" .. t.event .. "]") or ""
    table.insert(out, "      │" .. lbl)
    table.insert(out, "      ▼")
    if t.to == "[*]" then
      table.insert(out, "    ◉ [End]")
    else
      local s_box = make_box(t.to, "rounded", t.to)
      table.insert(out, "  " .. s_box.top)
      table.insert(out, "  " .. s_box.mid)
      table.insert(out, "  " .. s_box.bot)
    end
  end

  return frame_diagram(out, "󰡷 Mermaid State Machine (Live)")
end

-- =========================================================================
-- 3. FLOWCHART / GRAPH RENDERER
-- =========================================================================
local function render_flowchart(code)
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
    if not (line == "" or line:match("^%%") or line:match("^graph%s+") or line:match("^flowchart%s+")) then
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
    return frame_diagram({ "(Empty or unsupported Mermaid flowchart)" }, "󰡷 Mermaid Flowchart")
  end

  local boxes = {}
  for id, info in pairs(nodes) do
    boxes[id] = make_box(id, info.shape, info.label)
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
      table.insert(out, indent .. "└─ ⟲ (loops to [" .. (nodes[u] and nodes[u].label or u) .. "])")
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
      local lbl = (child.label and child.label ~= "") and ("  [" .. child.label .. "]") or ""
      table.insert(out, indent .. "      │" .. lbl)
      table.insert(out, indent .. "      ▼")
      draw_subgraph(child.to, indent)
    else
      for i, child in ipairs(children) do
        local is_last = (i == #children)
        local branch_char = is_last and "└" or "├"
        local lbl = (child.label and child.label ~= "") and (" [" .. child.label .. "] ──▶ ") or " ──▶ "
        table.insert(out, indent .. "      " .. branch_char .. "──────" .. lbl .. "[" .. (nodes[child.to] and nodes[child.to].label or child.to) .. "]")
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
  return frame_diagram(out, title)
end

-- =========================================================================
-- MAIN RENDER DISPATCHER
-- =========================================================================
function M.render(mermaid_code)
  local trimmed = vim.trim(mermaid_code)
  if trimmed:match("^sequenceDiagram") then
    return render_sequence(trimmed)
  elseif trimmed:match("^stateDiagram") then
    return render_state(trimmed)
  else
    return render_flowchart(trimmed)
  end
end

return M
