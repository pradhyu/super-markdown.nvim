local M = {}

local KEYWORDS = {
  ["graph"] = true,
  ["flowchart"] = true,
  ["sequencediagram"] = true,
  ["classdiagram"] = true,
  ["statediagram"] = true,
  ["statediagram-v2"] = true,
  ["erdiagram"] = true,
  ["gantt"] = true,
  ["pie"] = true,
  ["gitgraph"] = true,
  ["journey"] = true,
  ["mindmap"] = true,
  ["quadrantchart"] = true,
  ["xychart-beta"] = true,
  ["timeline"] = true,
  ["c4context"] = true,
  ["sankey-beta"] = true,
  ["subgraph"] = true,
  ["end"] = true,
  ["direction"] = true,
  ["classdef"] = true,
  ["class"] = true,
  ["style"] = true,
  ["linkstyle"] = true,
  ["click"] = true,
  ["interpolate"] = true,
  ["autonumber"] = true,
  ["actor"] = true,
  ["participant"] = true,
  ["as"] = true,
  ["note"] = true,
  ["over"] = true,
  ["loop"] = true,
  ["alt"] = true,
  ["else"] = true,
  ["opt"] = true,
  ["par"] = true,
  ["critical"] = true,
  ["break"] = true,
  ["rect"] = true,
  ["activate"] = true,
  ["deactivate"] = true,
  ["state"] = true,
  ["fork"] = true,
  ["join"] = true,
  ["choice"] = true,
  ["commit"] = true,
  ["branch"] = true,
  ["checkout"] = true,
  ["merge"] = true,
  ["tag"] = true,
  ["title"] = true,
  ["accTitle"] = true,
  ["accDescr"] = true,
}

local DIRECTIONS = {
  ["TD"] = true,
  ["TB"] = true,
  ["BT"] = true,
  ["RL"] = true,
  ["LR"] = true,
}

local ARROW_PATTERNS = {
  "^%-%-%>+>",
  "^%-%-%>+",
  "^%-%>+>",
  "^%-%>+",
  "^%-%-x",
  "^%-%-%)",
  "^%-%-%-",
  "^%-%-",
  "^%-%+%.%-%+%>?",
  "^%-%.%->?",
  "^%-%.%-",
  "^===%>?",
  "^==%>?",
  "^<|%-%-",
  "^%-%-%|>",
  "^<%-%-",
  "^<%-",
}

--- Tokenize a single mermaid code line into highlight tokens
--- @param line string
--- @return table Array of { col_start, col_end, hl_group } (0-indexed col_start, 1-indexed col_end)
function M.tokenize_line(line)
  local tokens = {}
  local len = #line
  local pos = 1

  -- 1. Check for comment (%%) first; comment spans to end of line
  local c_start, c_end = line:find("%%%%.*")
  local limit = len
  if c_start then
    table.insert(tokens, { c_start - 1, c_end, "SuperMarkdownMermaidComment" })
    limit = c_start - 1
  end

  while pos <= limit do
    -- Skip whitespace
    local s_start, s_end = line:find("^%s+", pos)
    if s_start then
      pos = s_end + 1
    end
    if pos > limit then break end

    local matched = false

    -- 2. Quoted strings: "..."
    local q_start, q_end = line:find('^"[^"]*"', pos)
    if q_start then
      table.insert(tokens, { q_start - 1, q_end, "SuperMarkdownMermaidString" })
      pos = q_end + 1
      matched = true
    end

    -- 3. Pipe edge labels: |label text|
    if not matched then
      local p_start, p_end = line:find('^|[^|]+|', pos)
      if p_start and p_end <= limit then
        table.insert(tokens, { p_start - 1, p_end, "SuperMarkdownMermaidEdgeLabel" })
        pos = p_end + 1
        matched = true
      end
    end

    -- 4. Arrows and connectors
    if not matched then
      for _, pat in ipairs(ARROW_PATTERNS) do
        local a_s, a_e = line:find(pat, pos)
        if a_s and a_e <= limit then
          table.insert(tokens, { a_s - 1, a_e, "SuperMarkdownMermaidArrow" })
          pos = a_e + 1
          matched = true
          break
        end
      end
    end

    -- 5. Node shapes & bracketed labels: [ ... ], ( ... ), { ... }, [( ... )], etc.
    if not matched then
      local b_start, b_end = line:find('^%b[]', pos)
      if not b_start then b_start, b_end = line:find('^%b()', pos) end
      if not b_start then b_start, b_end = line:find('^%b{}', pos) end
      if b_start and b_end <= limit then
        table.insert(tokens, { b_start - 1, b_end, "SuperMarkdownMermaidNodeLabel" })
        pos = b_end + 1
        matched = true
      end
    end

    -- 6. Sequence message separator (: message text)
    if not matched then
      local col_s, col_e = line:find('^:%s*(.+)$', pos)
      if col_s and col_e <= limit then
        table.insert(tokens, { col_s - 1, col_s, "SuperMarkdownMermaidArrow" })
        table.insert(tokens, { col_s, col_e, "SuperMarkdownMermaidNodeLabel" })
        pos = col_e + 1
        matched = true
      end
    end

    -- 7. Hex color codes: #abc, #123456
    if not matched then
      local h_start, h_end = line:find('^#[%x%d]+', pos)
      if h_start and h_end <= limit then
        table.insert(tokens, { h_start - 1, h_end, "SuperMarkdownMermaidNumber" })
        pos = h_end + 1
        matched = true
      end
    end

    -- 8. Words / Identifiers / Keywords
    if not matched then
      local w_start, w_end, word = line:find('^([%a_][%w_]*)', pos)
      if w_start and w_end <= limit then
        local lower = word:lower()
        if KEYWORDS[lower] then
          table.insert(tokens, { w_start - 1, w_end, "SuperMarkdownMermaidKeyword" })
        elseif DIRECTIONS[word] then
          table.insert(tokens, { w_start - 1, w_end, "SuperMarkdownMermaidType" })
        elseif word:match("^%d+$") then
          table.insert(tokens, { w_start - 1, w_end, "SuperMarkdownMermaidNumber" })
        else
          table.insert(tokens, { w_start - 1, w_end, "SuperMarkdownMermaidNodeId" })
        end
        pos = w_end + 1
        matched = true
      end
    end

    -- 9. Numeric values
    if not matched then
      local n_s, n_e = line:find('^%d+', pos)
      if n_s and n_e <= limit then
        table.insert(tokens, { n_s - 1, n_e, "SuperMarkdownMermaidNumber" })
        pos = n_e + 1
        matched = true
      end
    end

    -- 10. Fallback step
    if not matched then
      pos = pos + 1
    end
  end

  return tokens
end

--- Highlight a single mermaid line with extmarks
--- @param bufnr number Buffer number
--- @param ns_id number Namespace ID
--- @param lnum number 0-indexed line number
--- @param line string Line content
function M.highlight_line(bufnr, ns_id, lnum, line)
  if not line or line == "" then return end
  local tokens = M.tokenize_line(line)
  for _, tok in ipairs(tokens) do
    local c_start, c_end, hl = tok[1], tok[2], tok[3]
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, c_start, {
      end_col = c_end,
      hl_group = hl,
      priority = 100,
    })
  end
end

--- Highlight an entire mermaid code block
--- @param bufnr number Buffer number
--- @param ns_id number Namespace ID
--- @param start_row number 0-indexed start line (first line of mermaid code, after opening fence)
--- @param end_row number 0-indexed end line (last line of mermaid code, before closing fence)
--- @param lines table|nil Optional buffer lines
function M.highlight_block(bufnr, ns_id, start_row, end_row, lines)
  if start_row > end_row then return end
  if not lines then
    lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    for i, line in ipairs(lines) do
      M.highlight_line(bufnr, ns_id, start_row + i - 1, line)
    end
  else
    for row = start_row, end_row do
      local line = lines[row + 1]
      if line then
        M.highlight_line(bufnr, ns_id, row, line)
      end
    end
  end
end

return M
