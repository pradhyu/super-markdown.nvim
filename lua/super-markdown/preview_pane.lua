local config = require("super-markdown.config")
local highlights = require("super-markdown.highlights")
local tables = require("super-markdown.render.tables")
local ascii = require("super-markdown.mermaid.ascii")
local analyzer = require("super-markdown.spec.analyzer")
local link_tool = require("super-markdown.tools.link")

local M = {}

local preview_win = nil
local preview_buf = nil
local source_buf = nil
local source_win = nil
local augroup_id = nil
local debounce_timer = nil
local source_to_preview = {}
local preview_to_source = {}
local mermaid_cache = {}
local is_syncing = false
local last_synced_s_top = nil
local last_synced_s_cursor = nil
local last_synced_p_top = nil
local last_synced_p_cursor = nil
local NS_ID = vim.api.nvim_create_namespace("super_markdown_preview_pane")

function M.is_open()
  return preview_win ~= nil and vim.api.nvim_win_is_valid(preview_win)
end

function M.get_window()
  return preview_win
end

function M.get_buffer()
  return preview_buf
end

function M.get_line_maps()
  return source_to_preview, preview_to_source
end

--- Strips raw inline markdown formatting (`**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `[text](url)`, `\|`)
--- and returns the clean rendered string plus a list of byte-range highlight spans: `{ col_start, col_end, hl_group }` (0-indexed).
function M.format_inline(raw)
  local out = {}
  local out_len = 0
  local spans = {}
  local i = 1
  local len = #raw

  local function append(str, hl)
    if #str == 0 then return end
    local s_col = out_len
    table.insert(out, str)
    out_len = out_len + #str
    if hl then
      table.insert(spans, { s_col, out_len, hl })
    end
  end

  while i <= len do
    local ch = raw:sub(i, i)

    -- 1. Escaped character: \| \* \` etc.
    if ch == "\\" and i < len then
      append(raw:sub(i + 1, i + 1), nil)
      i = i + 2

    -- 2. Image or Link: ![alt](url) or [text](url)
    elseif (ch == "!" and raw:sub(i + 1, i + 1) == "[") or ch == "[" then
      local is_img = (ch == "!")
      local bracket_start = is_img and (i + 1) or i
      local s_end, e_end, text, _ = raw:find("^%[([^%]]+)%]%(([^%)]+)%)", bracket_start)
      if s_end then
        local icon = is_img and "󰥶 " or ((config.options.render.links and config.options.render.links.icon) or "󰌹 ")
        local clean_text, inner_spans = M.format_inline(text)
        local base = out_len + #icon
        append(icon .. clean_text, "SuperMarkdownLink")
        for _, sp in ipairs(inner_spans) do
          table.insert(spans, { base + sp[1], base + sp[2], sp[3] })
        end
        i = e_end + 1
      else
        append(ch, nil)
        i = i + 1
      end

    -- 3. Inline code span: `code` or ``code``
    elseif ch == "`" then
      local ticks = 1
      while i + ticks <= len and raw:sub(i + ticks, i + ticks) == "`" do
        ticks = ticks + 1
      end
      local close_pat = string.rep("`", ticks)
      local c_start, c_end = raw:find(close_pat, i + ticks, true)
      if c_start then
        local code_inner = raw:sub(i + ticks, c_start - 1)
        code_inner = code_inner:gsub("\\|", "|")
        append(code_inner, "SuperMarkdownInlineCode")
        i = c_end + 1
      else
        append(close_pat, nil)
        i = i + ticks
      end

    -- 4. Bold + Italic: ***text***
    elseif raw:sub(i, i + 2) == "***" then
      local c_start, c_end = raw:find("***", i + 3, true)
      if c_start then
        local inner, inner_spans = M.format_inline(raw:sub(i + 3, c_start - 1))
        local base = out_len
        append(inner, "SuperMarkdownBold")
        table.insert(spans, { base, out_len, "SuperMarkdownItalic" })
        for _, sp in ipairs(inner_spans) do
          table.insert(spans, { base + sp[1], base + sp[2], sp[3] })
        end
        i = c_end + 1
      else
        append("***", nil)
        i = i + 3
      end

    -- 5. Bold: **text** or __text__
    elseif raw:sub(i, i + 1) == "**" or raw:sub(i, i + 1) == "__" then
      local delim = raw:sub(i, i + 1)
      local c_start, c_end = raw:find(delim, i + 2, true)
      if c_start then
        local inner, inner_spans = M.format_inline(raw:sub(i + 2, c_start - 1))
        local base = out_len
        append(inner, "SuperMarkdownBold")
        for _, sp in ipairs(inner_spans) do
          table.insert(spans, { base + sp[1], base + sp[2], sp[3] })
        end
        i = c_end + 1
      else
        append(delim, nil)
        i = i + 2
      end

    -- 6. Strikethrough: ~~text~~
    elseif raw:sub(i, i + 1) == "~~" then
      local c_start, c_end = raw:find("~~", i + 2, true)
      if c_start then
        local inner, inner_spans = M.format_inline(raw:sub(i + 2, c_start - 1))
        local base = out_len
        append(inner, "SuperMarkdownCheckboxCanceled")
        for _, sp in ipairs(inner_spans) do
          table.insert(spans, { base + sp[1], base + sp[2], sp[3] })
        end
        i = c_end + 1
      else
        append("~~", nil)
        i = i + 2
      end

    -- 7. Italic: *text* or _text_ (only when not followed by space)
    elseif (ch == "*" or ch == "_") and raw:sub(i + 1, i + 1) ~= " " and raw:sub(i + 1, i + 1) ~= "" then
      local pat = (ch == "*") and "^%*([^%*]+)%*" or "^_([^_]+)_"
      local c_start, c_end, inner_raw = raw:find(pat, i)
      local prev_ch = (i > 1) and raw:sub(i - 1, i - 1) or ""
      if c_start == i and not (ch == "_" and prev_ch:match("[%w]")) then
        local inner, inner_spans = M.format_inline(inner_raw)
        local base = out_len
        append(inner, "SuperMarkdownItalic")
        for _, sp in ipairs(inner_spans) do
          table.insert(spans, { base + sp[1], base + sp[2], sp[3] })
        end
        i = c_end + 1
      else
        append(ch, nil)
        i = i + 1
      end

    else
      append(ch, nil)
      i = i + 1
    end
  end

  local final_str = table.concat(out)

  -- Highlight Requirement IDs (REQ-01, FR-01, etc.)
  local search_pos = 1
  while true do
    local s, e, req_id = final_str:find("([A-Z][A-Z0-9]?[A-Z0-9]?%-%d+)", search_pos)
    if not s then break end
    local prefix = req_id:match("^([A-Z]+)%-")
    if prefix == "REQ" or prefix == "FR" or prefix == "NFR" or prefix == "SEC" or prefix == "TC" or prefix == "UC" then
      table.insert(spans, { s - 1, e, "SuperMarkdownSpecReqId" })
    end
    search_pos = e + 1
  end

  -- Highlight @impl: and @test: traceability tags
  for _, role in ipairs({ "impl", "test" }) do
    local s, e = final_str:find("@" .. role .. "%s*:%s*[^%s,`%)%]]+")
    if s and e then
      local hl = (role == "test") and "SuperMarkdownSpecBadgeTest" or "SuperMarkdownSpecBadgeImpl"
      table.insert(spans, { s - 1, e, hl })
    end
  end

  return final_str, spans
end

local TS_LANG_ALIASES = {
  sh = "bash",
  zsh = "bash",
  shell = "bash",
  console = "bash",
  js = "javascript",
  jsx = "javascript",
  ts = "typescript",
  tsx = "tsx",
  py = "python",
  yml = "yaml",
  md = "markdown",
  rs = "rust",
  golang = "go",
  ["c++"] = "cpp",
  cxx = "cpp",
  hpp = "cpp",
  h = "c",
}

local TS_CAPTURE_FALLBACK = {
  keyword = "SuperMarkdownMermaidKeyword",
  ["function"] = "SuperMarkdownH1",
  method = "SuperMarkdownH1",
  string = "SuperMarkdownMermaidString",
  character = "SuperMarkdownMermaidString",
  comment = "SuperMarkdownMermaidComment",
  number = "SuperMarkdownMermaidNumber",
  float = "SuperMarkdownMermaidNumber",
  boolean = "SuperMarkdownMermaidNumber",
  constant = "SuperMarkdownMermaidNumber",
  type = "SuperMarkdownMermaidType",
  constructor = "SuperMarkdownMermaidType",
  operator = "SuperMarkdownMermaidArrow",
  property = "SuperMarkdownH2",
  field = "SuperMarkdownH2",
  variable = "SuperMarkdownBold",
  parameter = "SuperMarkdownMermaidNodeId",
  tag = "SuperMarkdownMermaidKeyword",
  attribute = "SuperMarkdownMermaidNodeId",
  punctuation = "SuperMarkdownTableBorder",
}

local function resolve_capture_hl(cap_name, ts_lang)
  local prefix = cap_name:match("^([^%.]+)") or cap_name
  if TS_CAPTURE_FALLBACK[prefix] then
    return TS_CAPTURE_FALLBACK[prefix]
  end
  local lang_hl = "@" .. cap_name .. "." .. ts_lang
  if vim.fn.hlexists(lang_hl) == 1 then
    return lang_hl
  end
  local base_hl = "@" .. cap_name
  if vim.fn.hlexists(base_hl) == 1 then
    return base_hl
  end
  return nil
end

local LEXICAL_KEYWORDS = {
  ["local"] = true, ["function"] = true, ["return"] = true, ["if"] = true, ["then"] = true,
  ["else"] = true, ["elseif"] = true, ["end"] = true, ["for"] = true, ["in"] = true,
  ["do"] = true, ["while"] = true, ["repeat"] = true, ["until"] = true, ["break"] = true,
  ["continue"] = true, ["def"] = true, ["class"] = true, ["import"] = true, ["from"] = true,
  ["as"] = true, ["pass"] = true, ["yield"] = true, ["async"] = true, ["await"] = true,
  ["with"] = true, ["try"] = true, ["except"] = true, ["finally"] = true, ["raise"] = true,
  ["const"] = true, ["let"] = true, ["var"] = true, ["export"] = true, ["default"] = true,
  ["new"] = true, ["typeof"] = true, ["instanceof"] = true, ["switch"] = true, ["case"] = true,
  ["fn"] = true, ["pub"] = true, ["mut"] = true, ["struct"] = true, ["enum"] = true,
  ["impl"] = true, ["trait"] = true, ["use"] = true, ["mod"] = true, ["match"] = true,
  ["where"] = true, ["crate"] = true, ["self"] = true, ["super"] = true, ["func"] = true,
  ["package"] = true, ["defer"] = true, ["go"] = true, ["select"] = true, ["interface"] = true,
  ["public"] = true, ["private"] = true, ["protected"] = true, ["static"] = true, ["final"] = true,
  ["abstract"] = true, ["extends"] = true, ["implements"] = true, ["throws"] = true, ["throw"] = true,
  ["record"] = true, ["synchronized"] = true, ["volatile"] = true, ["this"] = true,
  ["type"] = true, ["SELECT"] = true, ["FROM"] = true, ["WHERE"] = true, ["INSERT"] = true,
  ["INTO"] = true, ["VALUES"] = true, ["UPDATE"] = true, ["SET"] = true, ["DELETE"] = true,
  ["JOIN"] = true, ["LEFT"] = true, ["INNER"] = true, ["ON"] = true, ["GROUP"] = true,
  ["BY"] = true, ["ORDER"] = true, ["LIMIT"] = true, ["CREATE"] = true, ["TABLE"] = true,
  ["AND"] = true, ["OR"] = true, ["NOT"] = true, ["NULL"] = true, ["PRIMARY"] = true, ["KEY"] = true,
}

local LEXICAL_LITERALS = {
  ["true"] = true, ["false"] = true, ["nil"] = true, ["null"] = true,
  ["True"] = true, ["False"] = true, ["None"] = true, ["undefined"] = true,
}

local LEXICAL_TYPES = {
  ["string"] = true, ["number"] = true, ["boolean"] = true, ["table"] = true, ["any"] = true,
  ["void"] = true, ["int"] = true, ["float"] = true, ["double"] = true, ["char"] = true,
  ["bool"] = true, ["usize"] = true, ["isize"] = true, ["u8"] = true, ["u16"] = true,
  ["u32"] = true, ["u64"] = true, ["i8"] = true, ["i16"] = true, ["i32"] = true, ["i64"] = true,
  ["f32"] = true, ["f64"] = true, ["str"] = true, ["String"] = true, ["Vec"] = true,
  ["Option"] = true, ["Result"] = true, ["Map"] = true, ["List"] = true, ["Dict"] = true,
  ["INT"] = true, ["INTEGER"] = true, ["VARCHAR"] = true, ["TEXT"] = true, ["BOOLEAN"] = true,
  ["TIMESTAMP"] = true, ["SERIAL"] = true, ["UUID"] = true, ["JSONB"] = true,
}

--- Lexical fallback syntax highlighter for a single line of code (returns 0-indexed spans relative to line)
local function highlight_code_line_lexical(line, lang)
  local spans = {}
  local n = #line

  -- 1. Check full/trailing line comments (--, //, #)
  local c_start = nil
  if lang == "lua" or lang == "sql" then
    c_start = line:find("%-%-")
  elseif lang == "python" or lang == "bash" or lang == "sh" or lang == "zsh" or lang == "yaml" or lang == "toml" then
    c_start = line:find("#")
  else
    c_start = line:find("//") or line:find("#")
  end

  local code_end = c_start and (c_start - 1) or n

  -- 2. Highlight YAML/JSON/TOML key before colon/equals
  local k_s, k_e = line:find("^%s*([%w_%-%.\"']+)%s*:")
  if k_s and k_e and k_e <= code_end then
    local colon = line:find(":", k_s, true)
    if colon then
      table.insert(spans, { k_s - 1, colon - 1, "SuperMarkdownH2" })
    end
  end

  -- 3. Scan tokens up to comment start
  local idx = 1
  while idx <= code_end do
    local ch = line:sub(idx, idx)

    if ch == '"' or ch == "'" or ch == "`" then
      local q = ch
      local j = idx + 1
      while j <= code_end do
        local cj = line:sub(j, j)
        if cj == "\\" then
          j = j + 2
        elseif cj == q then
          j = j + 1
          break
        else
          j = j + 1
        end
      end
      table.insert(spans, { idx - 1, math.min(j - 1, code_end), "SuperMarkdownMermaidString" })
      idx = j
    elseif ch:match("%d") and (idx == 1 or not line:sub(idx - 1, idx - 1):match("[%w_]")) then
      local _, num_e = line:find("^[%da-fA-FxX%.]+", idx)
      if num_e then
        table.insert(spans, { idx - 1, math.min(num_e, code_end), "SuperMarkdownMermaidNumber" })
        idx = num_e + 1
      else
        idx = idx + 1
      end
    elseif ch:match("[%a_]") then
      local _, id_e, word = line:find("^([%a_][%w_]*)", idx)
      if id_e and word then
        local next_ch = line:sub(id_e + 1, id_e + 1)
        if LEXICAL_KEYWORDS[word] then
          table.insert(spans, { idx - 1, id_e, "SuperMarkdownMermaidKeyword" })
        elseif LEXICAL_LITERALS[word] then
          table.insert(spans, { idx - 1, id_e, "SuperMarkdownMermaidNumber" })
        elseif LEXICAL_TYPES[word] or word:match("^[A-Z][%w_]*$") then
          table.insert(spans, { idx - 1, id_e, "SuperMarkdownMermaidType" })
        elseif next_ch == "(" then
          table.insert(spans, { idx - 1, id_e, "SuperMarkdownH1" })
        end
        idx = id_e + 1
      else
        idx = idx + 1
      end
    elseif ch:match("[=%+%-%*/<>!&|:]") then
      local _, op_e = line:find("^[=%+%-%*/<>!&|:]+", idx)
      if op_e then
        table.insert(spans, { idx - 1, math.min(op_e, code_end), "SuperMarkdownMermaidArrow" })
        idx = op_e + 1
      else
        idx = idx + 1
      end
    else
      idx = idx + 1
    end
  end

  if c_start then
    table.insert(spans, { c_start - 1, n, "SuperMarkdownMermaidComment" })
  end

  return spans
end

--- Highlights a multi-line code block using Treesitter if available, falling back to lexical tokens.
--- Returns a table mapping 1-indexed line number -> list of `{ start_col, end_col, hl_group }` (0-indexed relative to code line).
local function highlight_code_block(code_lines, lang)
  local line_spans = {}
  for idx = 1, #code_lines do
    line_spans[idx] = {}
  end
  if #code_lines == 0 then
    return line_spans
  end

  local ts_lang = TS_LANG_ALIASES[lang] or lang
  local used_ts = false

  if ts_lang and ts_lang ~= "" then
    local code_str = table.concat(code_lines, "\n")
    local ok_p, parser = pcall(vim.treesitter.get_string_parser, code_str, ts_lang)
    if ok_p and parser then
      local ok_t, trees = pcall(function() return parser:parse() end)
      local ok_q, query = pcall(vim.treesitter.query.get, ts_lang, "highlights")
      if ok_t and trees and trees[1] and ok_q and query then
        local root = trees[1]:root()
        for id, node in query:iter_captures(root, code_str, 0, -1) do
          local cap = query.captures[id]
          if cap and cap ~= "spell" and cap ~= "nospell" then
            local hl = resolve_capture_hl(cap, ts_lang)
            if hl then
              local sr, sc, er, ec = node:range()
              for r = sr, er do
                local l_idx = r + 1
                if line_spans[l_idx] then
                  local line_len = #code_lines[l_idx]
                  local s_c = (r == sr) and sc or 0
                  local e_c = (r == er) and ec or line_len
                  if e_c > s_c then
                    table.insert(line_spans[l_idx], { s_c, math.min(line_len, e_c), hl })
                    used_ts = true
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  if not used_ts then
    for idx, c_line in ipairs(code_lines) do
      line_spans[idx] = highlight_code_line_lexical(c_line, ts_lang)
    end
  end

  return line_spans
end

--- Highlights a rendered ASCII Mermaid diagram line (`"  │ " .. d_line`) with distinct box, arrow, label & header colors
local function highlight_mermaid_diagram_line(padded_d)
  local spans = {
    { 0, 6, "SuperMarkdownCodeBorder" },
  }
  local len = #padded_d
  local i = 7
  while i <= len do
    -- Box drawing borders: ┌ ─ ┬ ┐ │ ├ ┼ ┤ └ ┴ ┘ ╭ ╮ ╰ ╯ ╔ ═ ╗ ║ ╚ ╝
    local b3 = padded_d:sub(i, i + 2)
    if
      b3 == "┌" or b3 == "─" or b3 == "┬" or b3 == "┐"
      or b3 == "│" or b3 == "├" or b3 == "┼" or b3 == "┤"
      or b3 == "└" or b3 == "┴" or b3 == "┘"
      or b3 == "╭" or b3 == "╮" or b3 == "╰" or b3 == "╯"
      or b3 == "╔" or b3 == "═" or b3 == "╗" or b3 == "║" or b3 == "╚" or b3 == "╝"
      or b3 == "┼"
    then
      table.insert(spans, { i - 1, i + 2, "SuperMarkdownMermaidType" })
      i = i + 3
    elseif b3 == "▶" or b3 == "◀" or b3 == "▲" or b3 == "▼" or b3 == "●" or b3 == "○" then
      table.insert(spans, { i - 1, i + 2, "SuperMarkdownMermaidArrow" })
      i = i + 3
    else
      local ch = padded_d:sub(i, i)
      if ch == "[" then
        local c_e = padded_d:find("%]", i + 1)
        if c_e then
          table.insert(spans, { i - 1, c_e, "SuperMarkdownMermaidEdgeLabel" })
          i = c_e + 1
        else
          i = i + 1
        end
      elseif ch == ":" then
        table.insert(spans, { i - 1, i, "SuperMarkdownMermaidArrow" })
        i = i + 1
      elseif ch ~= " " then
        local s_e = i
        while s_e <= len do
          local nb3 = padded_d:sub(s_e, s_e + 2)
          local nch = padded_d:sub(s_e, s_e)
          if
            nb3 == "┌" or nb3 == "─" or nb3 == "┬" or nb3 == "┐"
            or nb3 == "│" or nb3 == "├" or nb3 == "┼" or nb3 == "┤"
            or nb3 == "└" or nb3 == "┴" or nb3 == "┘"
            or nb3 == "╭" or nb3 == "╮" or nb3 == "╰" or nb3 == "╯"
            or nb3 == "╔" or nb3 == "═" or nb3 == "╗" or nb3 == "║" or nb3 == "╚" or nb3 == "╝"
            or nb3 == "▶" or nb3 == "◀" or nb3 == "▲" or nb3 == "▼"
            or nch == "["
          then
            break
          end
          s_e = s_e + 1
        end
        table.insert(spans, { i - 1, s_e - 1, "SuperMarkdownMermaidNodeLabel" })
        i = s_e
      else
        i = i + 1
      end
    end
  end
  return spans
end

--- Renders a contiguous Markdown table block into pure Unicode box-drawn lines with inline spans
local function compile_table_block(src_lines, start_idx, end_idx, opts)
  local hl_border = (opts and opts.hl) or "SuperMarkdownTableBorder"
  local hl_header = (opts and opts.header_hl) or "SuperMarkdownTableHeader"
  local c = (opts and opts.corners) or {
    top_left = "┌", top_mid = "┬", top_right = "┐",
    mid_left = "├", mid_mid = "┼", mid_right = "┤",
    bot_left = "└", bot_mid = "┴", bot_right = "┘",
  }
  local head_sep = (opts and opts.head_sep) or "─"
  local vertical = (opts and opts.vertical) or "│"

  local rows = {}
  local sep_row_idx = nil
  local num_cols = 0

  for idx = start_idx, end_idx do
    local line = src_lines[idx]
    local is_sep = tables.is_table_separator(line)
    if is_sep and not sep_row_idx then
      sep_row_idx = #rows + 1
    end

    local pipes = tables.find_unescaped_pipes(line)
    local cells = {}
    for i = 1, #pipes - 1 do
      local raw_c = vim.trim(line:sub(pipes[i] + 1, pipes[i + 1] - 1))
      if is_sep then
        table.insert(cells, { text = raw_c, width = vim.fn.strdisplaywidth(raw_c), spans = {} })
      else
        local clean, sp = M.format_inline(raw_c)
        table.insert(cells, {
          text = clean,
          width = vim.fn.strdisplaywidth(clean),
          spans = sp,
        })
      end
    end
    if #cells > num_cols then
      num_cols = #cells
    end
    table.insert(rows, { src_lnum = idx, is_sep = is_sep, cells = cells })
  end

  if num_cols == 0 then
    return {}, {}
  end

  local aligns = {}
  if sep_row_idx and rows[sep_row_idx] then
    for i = 1, num_cols do
      local cell = rows[sep_row_idx].cells[i]
      local t = cell and cell.text or ""
      local l_col = t:sub(1, 1) == ":"
      local r_col = t:sub(-1) == ":"
      aligns[i] = (l_col and r_col and "center") or (r_col and "right") or "left"
    end
  else
    for i = 1, num_cols do aligns[i] = "left" end
  end

  local col_widths = {}
  for i = 1, num_cols do col_widths[i] = 3 end
  for _, r in ipairs(rows) do
    if not r.is_sep then
      for i = 1, num_cols do
        local cell = r.cells[i]
        if cell and cell.width > col_widths[i] then
          col_widths[i] = cell.width
        end
      end
    end
  end

  local out_lines = {}
  local out_meta = {} -- { src_lnum = number, spans = {}, line_hl = nil }

  -- 1. Top border
  local top_segs = { "  " .. c.top_left }
  for i = 1, num_cols do
    table.insert(top_segs, string.rep(head_sep, col_widths[i] + 2))
    table.insert(top_segs, (i < num_cols) and c.top_mid or c.top_right)
  end
  local top_str = table.concat(top_segs)
  table.insert(out_lines, top_str)
  table.insert(out_meta, {
    src_lnum = start_idx,
    spans = { { 0, #top_str, hl_border } },
  })

  -- 2. Rows
  for r_i, r in ipairs(rows) do
    local is_header = sep_row_idx and (r_i < sep_row_idx)
    if r.is_sep then
      local mid_segs = { "  " .. c.mid_left }
      for i = 1, num_cols do
        table.insert(mid_segs, string.rep(head_sep, col_widths[i] + 2))
        table.insert(mid_segs, (i < num_cols) and c.mid_mid or c.mid_right)
      end
      local mid_str = table.concat(mid_segs)
      table.insert(out_lines, mid_str)
      table.insert(out_meta, {
        src_lnum = r.src_lnum,
        spans = { { 0, #mid_str, hl_border } },
      })
    else
      local row_parts = { "  " }
      local row_len = 2
      local row_spans = {}

      local function add_part(s, hl)
        local s_col = row_len
        table.insert(row_parts, s)
        row_len = row_len + #s
        if hl then
          table.insert(row_spans, { s_col, row_len, hl })
        end
      end

      add_part(vertical, hl_border)
      for i = 1, num_cols do
        local cell = r.cells[i] or { text = "", width = 0, spans = {} }
        local pad = math.max(0, col_widths[i] - cell.width)
        local align = aligns[i]
        local pad_l, pad_r = 0, pad
        if align == "right" then
          pad_l, pad_r = pad, 0
        elseif align == "center" then
          pad_l = math.floor(pad / 2)
          pad_r = pad - pad_l
        end

        add_part(" " .. string.rep(" ", pad_l), nil)
        local cell_start = row_len
        add_part(cell.text, is_header and hl_header or nil)
        for _, sp in ipairs(cell.spans) do
          table.insert(row_spans, { cell_start + sp[1], cell_start + sp[2], sp[3] })
        end
        add_part(string.rep(" ", pad_r) .. " ", nil)
        add_part(vertical, hl_border)
      end

      table.insert(out_lines, table.concat(row_parts))
      table.insert(out_meta, {
        src_lnum = r.src_lnum,
        spans = row_spans,
      })
    end
  end

  -- 3. Bottom border
  local bot_segs = { "  " .. c.bot_left }
  for i = 1, num_cols do
    table.insert(bot_segs, string.rep(head_sep, col_widths[i] + 2))
    table.insert(bot_segs, (i < num_cols) and c.bot_mid or c.bot_right)
  end
  local bot_str = table.concat(bot_segs)
  table.insert(out_lines, bot_str)
  table.insert(out_meta, {
    src_lnum = end_idx,
    spans = { { 0, #bot_str, hl_border } },
  })

  return out_lines, out_meta
end

--- Compiles the entire source Markdown buffer into a clean, fully rendered read-only document
function M.compile_document(bufnr, win_width)
  local src_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local r_opts = (config.options and config.options.render) or {}
  win_width = win_width or 72

  local sec_by_lnum = {}
  local ok_an, analysis = pcall(analyzer.analyze, bufnr)
  if ok_an and analysis and analysis.sections then
    for _, sec in ipairs(analysis.sections) do
      sec_by_lnum[sec.lnum] = sec
    end
  end

  local out_lines = {}
  local out_meta = {}
  local s2p = {}
  local p2s = {}

  local function push_line(text, src_lnum, meta)
    meta = meta or {}
    table.insert(out_lines, text)
    local p_idx = #out_lines
    meta.src_lnum = src_lnum
    out_meta[p_idx] = meta
    p2s[p_idx] = src_lnum
    if src_lnum and not s2p[src_lnum] then
      s2p[src_lnum] = p_idx
    end
  end

  local i = 1
  local n = #src_lines
  local prev_callout = nil

  while i <= n do
    local line = src_lines[i]

    -- 1. Fenced Code Block (Mermaid or standard code block)
    local indent, lang = line:match("^(%s*)```+([%w_%-%+]*)(.*)$")
    local fence_char = "`"
    if not indent then
      indent, lang = line:match("^(%s*)~~~+([%w_%-%+]*)(.*)$")
      fence_char = "~"
    end

    if indent then
      local lang_clean = vim.trim(lang):lower()
      local block_start = i
      local code_lines = {}
      i = i + 1
      local close_pat = (fence_char == "~") and "^%s*~~~+%s*$" or "^%s*```+%s*$"
      while i <= n and not src_lines[i]:match(close_pat) do
        table.insert(code_lines, src_lines[i])
        i = i + 1
      end
      local block_end = math.min(i, n)

      if lang_clean == "mermaid" or lang_clean == "mmd" then
        -- Render Mermaid diagram directly in the preview buffer (hiding raw code!)
        -- Include window width in cache key so resizing re-renders diagram layout to fit
        local code = table.concat(code_lines, "\n")
        local inner_max_w = math.max(28, win_width - 8)
        local hash = vim.fn.sha256(code .. ":" .. tostring(inner_max_w))
        local diagram_lines = mermaid_cache[hash]
        if not diagram_lines then
          diagram_lines = ascii.render(code, { max_width = inner_max_w, bare = true })
          mermaid_cache[hash] = diagram_lines
        end

        local diag_w = 38
        for _, dl in ipairs(diagram_lines) do
          local w = vim.fn.strdisplaywidth(dl)
          if w > diag_w then
            diag_w = w
          end
        end
        local box_inner_w = math.max(diag_w + 2, math.min(inner_max_w, math.max(44, win_width - 8)))
        local title_badge = "󰡷 Mermaid Diagram (Live Preview)"
        local title_w = vim.fn.strdisplaywidth(title_badge)
        local top_dashes = string.rep("─", math.max(2, box_inner_w - title_w - 3))
        local header_str = "  ╭─ " .. title_badge .. " " .. top_dashes .. "╮"
        push_line(header_str, block_start, {
          spans = {
            { 0, #header_str, "SuperMarkdownCodeBorder" },
            { 7, 7 + #title_badge, "SuperMarkdownMermaidReady" },
          },
        })
        local p_block_start = #out_lines

        for d_idx, d_line in ipairs(diagram_lines) do
          local ratio = (#diagram_lines > 1) and ((d_idx - 1) / (#diagram_lines - 1)) or 0
          local mapped_src = block_start + math.floor(ratio * math.max(0, block_end - block_start) + 0.5)
          mapped_src = math.min(block_end, math.max(block_start, mapped_src))
          local dl_w = vim.fn.strdisplaywidth(d_line)
          local r_pad = string.rep(" ", math.max(1, box_inner_w - dl_w - 1))
          local padded_d = "  │ " .. d_line .. r_pad .. "│"
          local d_spans = highlight_mermaid_diagram_line(padded_d)
          table.insert(d_spans, { #padded_d - 3, #padded_d, "SuperMarkdownCodeBorder" })
          push_line(padded_d, mapped_src, {
            line_hl = "SuperMarkdownCodeBlock",
            spans = d_spans,
          })
        end

        local footer_str = "  ╰" .. string.rep("─", box_inner_w) .. "╯"
        push_line(footer_str, block_end, {
          spans = { { 0, #footer_str, "SuperMarkdownCodeBorder" } },
        })
        local p_block_end = #out_lines

        -- Uniform block-stepping across [block_start .. block_end] -> [p_block_start .. p_block_end]
        for s_l = block_start, block_end do
          local ratio = (block_end > block_start) and ((s_l - block_start) / (block_end - block_start)) or 0
          s2p[s_l] = p_block_start + math.floor(ratio * (p_block_end - p_block_start) + 0.5)
        end
      else
        -- Render styled Code Block without raw ``` fences, with full syntax highlighting
        local cb_opts = r_opts.codeblocks or {}
        local badge = (cb_opts.language_icons and cb_opts.language_icons[lang_clean])
          or (lang_clean ~= "" and ("󰅩 " .. lang_clean) or "󰅩 code")
        local badge_w = vim.fn.strdisplaywidth(badge)
        local box_w = math.max(48, win_width - 8)
        local top_fill = string.rep("─", math.max(4, box_w - badge_w - 5))
        local top_line = "  ╭─ " .. badge .. " " .. top_fill .. "╮"
        push_line(top_line, block_start, {
          spans = {
            { 0, #top_line, "SuperMarkdownCodeBorder" },
            { 7, 7 + #badge, "SuperMarkdownCodeLang" },
          },
        })

        local code_hl_map = highlight_code_block(code_lines, lang_clean)
        local code_prefix = "  │ "
        local prefix_bytes = #code_prefix
        for c_idx, c_line in ipairs(code_lines) do
          local src_l = block_start + c_idx
          local disp = code_prefix .. c_line
          local line_spans = { { 0, prefix_bytes, "SuperMarkdownCodeBorder" } }
          for _, sp in ipairs(code_hl_map[c_idx] or {}) do
            table.insert(line_spans, { prefix_bytes + sp[1], prefix_bytes + sp[2], sp[3] })
          end
          push_line(disp, src_l, {
            line_hl = "SuperMarkdownCodeBlock",
            spans = line_spans,
          })
        end

        local bot_line = "  ╰" .. string.rep("─", math.max(6, box_w)) .. "╯"
        push_line(bot_line, block_end, {
          spans = { { 0, #bot_line, "SuperMarkdownCodeBorder" } },
        })
      end

      prev_callout = nil
      i = i + 1

    -- 2. Contiguous Markdown Table Block
    elseif tables.is_table_row(line) then
      local tbl_start = i
      local tbl_end = i
      while tbl_end + 1 <= n and tables.is_table_row(src_lines[tbl_end + 1]) do
        tbl_end = tbl_end + 1
      end

      local t_lines, t_meta = compile_table_block(src_lines, tbl_start, tbl_end, r_opts.tables)
      local p_tbl_start = #out_lines + 1
      for t_i, tl in ipairs(t_lines) do
        local m = t_meta[t_i] or {}
        local s_l = m.src_lnum or tbl_start
        push_line(tl, s_l, m)
      end
      local p_tbl_end = #out_lines
      for s_l = tbl_start, tbl_end do
        local ratio = (tbl_end > tbl_start) and ((s_l - tbl_start) / (tbl_end - tbl_start)) or 0
        s2p[s_l] = p_tbl_start + math.floor(ratio * (p_tbl_end - p_tbl_start) + 0.5)
      end

      prev_callout = nil
      i = tbl_end + 1

    -- 3. Headings (# H1 .. ###### H6)
    elseif line:match("^(#+)%s+(.*)$") then
      local hashes, title = line:match("^(#+)%s+(.*)$")
      local level = math.min(6, #hashes)
      local h_opts = r_opts.headings or {}
      local icon = (h_opts.icons and h_opts.icons[level]) or "󰲡 "
      local fg_hl = (h_opts.foregrounds and h_opts.foregrounds[level]) or ("SuperMarkdownH" .. level)
      local bg_hl = (h_opts.backgrounds and h_opts.backgrounds[level]) or ("SuperMarkdownH" .. level .. "Bg")

      local clean_title, inline_spans = M.format_inline(title)
      local prefix = " " .. string.rep("  ", math.max(0, level - 1)) .. icon
      local full_line = prefix .. clean_title
      local spans = {
        { 0, #full_line, fg_hl },
      }
      for _, sp in ipairs(inline_spans) do
        table.insert(spans, { #prefix + sp[1], #prefix + sp[2], sp[3] })
      end

      -- Append Spec task rollup badges if present
      local sec = sec_by_lnum[i]
      if sec and sec.counts and sec.counts.total_tasks and sec.counts.total_tasks > 0 then
        local done = sec.counts.checked or 0
        local badge = string.format("  [󰄵 %d/%d]", done, sec.counts.total_tasks)
        local b_start = #full_line
        full_line = full_line .. badge
        local b_hl = (done == sec.counts.total_tasks) and "SuperMarkdownCheckboxChecked" or "SuperMarkdownCheckboxProgress"
        table.insert(spans, { b_start, #full_line, b_hl })
      end

      push_line(full_line, i, {
        line_hl = level <= 2 and bg_hl or nil,
        spans = spans,
      })
      prev_callout = nil
      i = i + 1

    -- 4. Horizontal Divider (---, ***, ___)
    elseif line:match("^%s*%-%s*%-%s*%-[%s%-]*$")
      or line:match("^%s*%*%s*%*%s*%*[%s%*]*$")
      or line:match("^%s*_%s*_%s*_[%s_]*$") then
      local d_char = (r_opts.dividers and r_opts.dividers.char) or "─"
      local d_str = " " .. string.rep(d_char, math.max(30, win_width - 6))
      push_line(d_str, i, {
        spans = { { 0, #d_str, "SuperMarkdownDivider" } },
      })
      prev_callout = nil
      i = i + 1

    -- 5. Callouts & Blockquotes (> [!NOTE] or > quote)
    elseif line:match("^%s*>") then
      local _, c_type, c_title = line:match("^(%s*>%s*)%[!([%w_%-]+)%]%s*(.*)$")
      local c_opts = r_opts.callouts or {}
      local border_char = c_opts.border_char or "▍"

      if c_type then
        local upper = c_type:upper()
        local c_info = (c_opts.types and c_opts.types[upper]) or {
          icon = "󰋽 ",
          title = upper:sub(1, 1) .. upper:sub(2):lower(),
          hl = "SuperMarkdownCalloutNote",
        }
        local disp_title = (c_title and #c_title > 0) and M.format_inline(c_title) or c_info.title
        local out_str = "  " .. border_char .. " " .. c_info.icon .. disp_title
        push_line(out_str, i, {
          spans = { { 0, #out_str, c_info.hl } },
        })
        prev_callout = c_info
      else
        local q_body = line:gsub("^%s*>%s?", "")
        local clean_body, sp = M.format_inline(q_body)
        local hl = (prev_callout and prev_callout.hl) or "SuperMarkdownCalloutNote"
        local prefix = "  " .. border_char .. " "
        local out_str = prefix .. clean_body
        local spans = { { 0, #prefix, hl } }
        for _, s in ipairs(sp) do
          table.insert(spans, { #prefix + s[1], #prefix + s[2], s[3] })
        end
        push_line(out_str, i, { spans = spans })
      end
      i = i + 1

    -- 6. Task Checkboxes (- [ ] / - [x] / - [/] / - [!] / - [?])
    elseif line:match("^(%s*[%-%*%+]%s+)%[([%s%w%-%/%!%?])%](.*)$") then
      local l_indent, mark, rest = line:match("^(%s*)[%-%*%+]%s+%[([%s%w%-%/%!%?])%](.*)$")
      local cb_icons = (r_opts.checkboxes and r_opts.checkboxes.icons) or {}
      local m = mark:lower()
      local info = cb_icons.unchecked or { icon = "󰄱 ", hl = "SuperMarkdownCheckboxUnchecked" }
      if m == "x" then
        info = cb_icons.checked or { icon = "󰄵 ", hl = "SuperMarkdownCheckboxChecked" }
      elseif m == "-" then
        info = cb_icons.canceled or { icon = "󰡖 ", hl = "SuperMarkdownCheckboxCanceled" }
      elseif m == "/" then
        info = cb_icons.progress or { icon = "󰄰 ", hl = "SuperMarkdownCheckboxProgress" }
      elseif m == "!" then
        info = cb_icons.important or { icon = "󰀦 ", hl = "SuperMarkdownCheckboxImportant" }
      elseif m == "?" then
        info = cb_icons.question or { icon = "󰋽 ", hl = "SuperMarkdownCheckboxQuestion" }
      end

      local clean_rest, sp = M.format_inline(rest)
      local prefix = "  " .. l_indent .. info.icon
      local out_str = prefix .. clean_rest
      local spans = { { 0, #prefix, info.hl } }
      if m == "-" then
        table.insert(spans, { #prefix, #out_str, "SuperMarkdownCheckboxCanceled" })
      end
      for _, s in ipairs(sp) do
        table.insert(spans, { #prefix + s[1], #prefix + s[2], s[3] })
      end
      push_line(out_str, i, { spans = spans })
      prev_callout = nil
      i = i + 1

    -- 7. Bullet Lists (- / * / +)
    elseif line:match("^(%s*)[%-%*%+]%s+(.*)$") then
      local l_indent, rest = line:match("^(%s*)[%-%*%+]%s+(.*)$")
      local depth = math.floor(#l_indent / 2)
      local bullets = { "• ", "◦ ", "▪ ", "▫ " }
      local bullet = bullets[(depth % #bullets) + 1]
      local clean_rest, sp = M.format_inline(rest)
      local prefix = "  " .. l_indent .. bullet
      local out_str = prefix .. clean_rest
      local spans = { { 0, #prefix, "SuperMarkdownH2" } }
      for _, s in ipairs(sp) do
        table.insert(spans, { #prefix + s[1], #prefix + s[2], s[3] })
      end
      push_line(out_str, i, { spans = spans })
      prev_callout = nil
      i = i + 1

    -- 8. Ordered Lists (1. / 2.)
    elseif line:match("^(%s*%d+%.)%s+(.*)$") then
      local num_prefix, rest = line:match("^(%s*%d+%.)%s+(.*)$")
      local clean_rest, sp = M.format_inline(rest)
      local prefix = "  " .. num_prefix .. " "
      local out_str = prefix .. clean_rest
      local spans = { { 0, #prefix, "SuperMarkdownH3" } }
      for _, s in ipairs(sp) do
        table.insert(spans, { #prefix + s[1], #prefix + s[2], s[3] })
      end
      push_line(out_str, i, { spans = spans })
      prev_callout = nil
      i = i + 1

    -- 9. Regular Paragraph / Blank Line
    else
      if vim.trim(line) == "" then
        push_line("", i, {})
      else
        local clean_line, sp = M.format_inline(line)
        local prefix = "  "
        local out_str = prefix .. clean_line
        local spans = {}
        for _, s in ipairs(sp) do
          table.insert(spans, { #prefix + s[1], #prefix + s[2], s[3] })
        end
        push_line(out_str, i, { spans = spans })
      end
      prev_callout = nil
      i = i + 1
    end
  end

  return out_lines, out_meta, s2p, p2s
end

function M.refresh()
  if not (M.is_open() and preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then
    return
  end
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then
    return
  end

  highlights.setup()

  local win_w = vim.api.nvim_win_get_width(preview_win)
  local out_lines, out_meta, s2p, p2s = M.compile_document(source_buf, win_w)
  source_to_preview = s2p
  preview_to_source = p2s

  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].readonly = false
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, out_lines)
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].readonly = true
  vim.bo[preview_buf].modified = false

  vim.api.nvim_buf_clear_namespace(preview_buf, NS_ID, 0, -1)

  for p_idx, meta in ipairs(out_meta) do
    local lnum = p_idx - 1
    if meta.line_hl then
      pcall(vim.api.nvim_buf_set_extmark, preview_buf, NS_ID, lnum, 0, {
        line_hl_group = meta.line_hl,
        priority = 80,
      })
    end
    if meta.spans then
      for s_idx, sp in ipairs(meta.spans) do
        pcall(vim.api.nvim_buf_set_extmark, preview_buf, NS_ID, lnum, sp[1], {
          end_col = sp[2],
          hl_group = sp[3],
          priority = 90 + math.min(100, s_idx),
        })
      end
    end
  end

  M.sync_scroll()
end

function M.debounced_refresh()
  if not M.is_open() then return end
  if debounce_timer then
    debounce_timer:stop()
  else
    debounce_timer = vim.uv.new_timer()
  end
  debounce_timer:start(
    50,
    0,
    vim.schedule_wrap(function()
      if M.is_open() then
        M.refresh()
      end
    end)
  )
end

local function resolve_source_win()
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    if not source_buf or vim.api.nvim_win_get_buf(source_win) == source_buf then
      return source_win
    end
  end
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= preview_win and vim.api.nvim_win_get_buf(w) == source_buf then
        source_win = w
        return w
      end
    end
  end
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    return source_win
  end
  return nil
end

local function map_source_to_preview(src_lnum)
  if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then
    return 1
  end
  local total_p = math.max(1, vim.api.nvim_buf_line_count(preview_buf))
  local target = source_to_preview[src_lnum]
  if not target then
    for l = src_lnum, 1, -1 do
      if source_to_preview[l] then
        target = source_to_preview[l]
        break
      end
    end
  end
  if not target and source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    local total_s = vim.api.nvim_buf_line_count(source_buf)
    for l = src_lnum + 1, total_s do
      if source_to_preview[l] then
        target = source_to_preview[l]
        break
      end
    end
  end
  return math.max(1, math.min(total_p, target or 1))
end

local function map_preview_to_source(p_lnum)
  if not (source_buf and vim.api.nvim_buf_is_valid(source_buf)) then
    return 1
  end
  local total_s = math.max(1, vim.api.nvim_buf_line_count(source_buf))
  local target = preview_to_source[p_lnum]
  if not target then
    for l = p_lnum, 1, -1 do
      if preview_to_source[l] then
        target = preview_to_source[l]
        break
      end
    end
  end
  if not target and preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    local total_p = vim.api.nvim_buf_line_count(preview_buf)
    for l = p_lnum + 1, total_p do
      if preview_to_source[l] then
        target = preview_to_source[l]
        break
      end
    end
  end
  return math.max(1, math.min(total_s, target or 1))
end

local function get_sync_flags()
  local p_opts = (config.options and config.options.preview_pane) or {}
  local enabled = (p_opts.sync_scroll ~= false)
  local from_src = enabled and (p_opts.sync_from_source ~= false)
  local from_prv = enabled and (p_opts.sync_from_preview ~= false)
  return from_src, from_prv
end

local function get_sync_label()
  local from_src, from_prv = get_sync_flags()
  if from_src and from_prv then
    return "Sync: Both"
  elseif from_src then
    return "Sync: Source→Preview"
  elseif from_prv then
    return "Sync: Preview→Source"
  else
    return "Sync: Off"
  end
end

local function update_winbar()
  if not M.is_open() then
    return
  end
  local src_name = (source_buf and vim.api.nvim_buf_is_valid(source_buf))
      and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(source_buf), ":t")
    or "Markdown"
  if src_name == "" then
    src_name = "Markdown"
  end
  pcall(
    vim.api.nvim_set_option_value,
    "winbar",
    string.format(
      " 󰍔 SuperMarkdown Live Preview — %s [%s | s: Cycle Sync | <CR>/Double-Click: Edit | q: Close] ",
      src_name,
      get_sync_label()
    ),
    { win = preview_win }
  )
end

--- Set or cycle scroll synchronization mode: "both", "source", "preview", "off", or nil to cycle
function M.set_sync(mode)
  config.options.preview_pane = config.options.preview_pane or {}
  local p_opts = config.options.preview_pane

  if not mode or mode == "" or mode == "toggle" or mode == "cycle" then
    local from_src, from_prv = get_sync_flags()
    if from_src and from_prv then
      mode = "source"
    elseif from_src then
      mode = "preview"
    elseif from_prv then
      mode = "off"
    else
      mode = "both"
    end
  end

  mode = mode:lower()
  if mode == "both" or mode == "on" or mode == "all" then
    p_opts.sync_scroll = true
    p_opts.sync_from_source = true
    p_opts.sync_from_preview = true
  elseif mode == "source" or mode == "editor" or mode == "from_source" then
    p_opts.sync_scroll = true
    p_opts.sync_from_source = true
    p_opts.sync_from_preview = false
  elseif mode == "preview" or mode == "from_preview" then
    p_opts.sync_scroll = true
    p_opts.sync_from_source = false
    p_opts.sync_from_preview = true
  elseif mode == "off" or mode == "none" or mode == "false" or mode == "disable" then
    p_opts.sync_scroll = false
    p_opts.sync_from_source = false
    p_opts.sync_from_preview = false
  else
    vim.notify(
      "SuperMarkdown: Invalid preview_sync mode '" .. mode .. "' (use: both, source, preview, off)",
      vim.log.levels.WARN
    )
    return
  end

  update_winbar()
  vim.notify("SuperMarkdown Preview " .. get_sync_label() .. " 󰑐", vim.log.levels.INFO)
end

--- Sync preview pane cursor & viewport from editable source window
function M.sync_from_source()
  local from_src, _ = get_sync_flags()
  if not from_src or is_syncing or not M.is_open() then
    return
  end
  if vim.api.nvim_get_current_win() == preview_win then
    return
  end
  local s_win = resolve_source_win()
  if not s_win then
    return
  end

  is_syncing = true
  local ok, _ = pcall(function()
    local src_cursor = vim.api.nvim_win_get_cursor(s_win)[1]
    local src_top = vim.fn.line("w0", s_win)
    local target_p_line = map_source_to_preview(src_cursor)
    local total_p = math.max(1, vim.api.nvim_buf_line_count(preview_buf))
    local p_lnum = math.max(1, math.min(total_p, target_p_line))

    -- Maintain exact relative window line offset in 1-to-1 sections and step proportionally across blocks
    local offset = math.max(0, src_cursor - src_top)
    local p_top = math.max(1, math.min(p_lnum, p_lnum - offset))

    vim.api.nvim_win_call(preview_win, function()
      vim.fn.winrestview({ lnum = p_lnum, topline = p_top, col = 0 })
    end)
    vim.api.nvim_win_set_cursor(preview_win, { p_lnum, 0 })
  end)
  is_syncing = false
  return ok
end

--- Sync editable source window cursor & viewport from preview pane
function M.sync_from_preview()
  local _, from_prv = get_sync_flags()
  if not from_prv or is_syncing or not M.is_open() then
    return
  end
  if vim.api.nvim_get_current_win() ~= preview_win then
    return
  end
  local s_win = resolve_source_win()
  if not s_win then
    return
  end

  is_syncing = true
  local ok, _ = pcall(function()
    local p_cursor = vim.api.nvim_win_get_cursor(preview_win)[1]
    local p_top = vim.fn.line("w0", preview_win)
    local target_s_line = map_preview_to_source(p_cursor)
    local total_s = math.max(1, vim.api.nvim_buf_line_count(source_buf))
    local s_lnum = math.max(1, math.min(total_s, target_s_line))

    local offset = math.max(0, p_cursor - p_top)
    local s_top = math.max(1, math.min(s_lnum, s_lnum - offset))

    vim.api.nvim_win_call(s_win, function()
      vim.fn.winrestview({ lnum = s_lnum, topline = s_top, col = 0 })
    end)
    vim.api.nvim_win_set_cursor(s_win, { s_lnum, 0 })
  end)
  is_syncing = false
  return ok
end

function M.sync_scroll()
  if not M.is_open() then
    return
  end
  if vim.api.nvim_get_current_win() == preview_win then
    M.sync_from_preview()
  else
    M.sync_from_source()
  end
end

function M.jump_to_source()
  if not M.is_open() then
    return
  end
  local s_win = resolve_source_win()
  if not s_win then
    return
  end

  local p_cursor = vim.api.nvim_win_get_cursor(preview_win)[1]
  local p_top = vim.fn.line("w0", preview_win)
  local src_lnum = map_preview_to_source(p_cursor)
  local offset = math.max(0, p_cursor - p_top)
  local src_top = math.max(1, math.min(src_lnum, src_lnum - offset))

  is_syncing = true
  vim.api.nvim_set_current_win(s_win)
  pcall(vim.api.nvim_win_set_cursor, s_win, { src_lnum, 0 })
  pcall(vim.api.nvim_win_call, s_win, function()
    vim.cmd("normal! zv")
    vim.fn.winrestview({ lnum = src_lnum, topline = src_top, col = 0 })
  end)
  is_syncing = false

  M.sync_from_source()
end

function M.close()
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end
  if augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
    augroup_id = nil
  end

  local win_to_close = preview_win
  local buf_to_delete = preview_buf
  local prev_win = source_win
  local prev_buf = source_buf

  preview_win = nil
  preview_buf = nil
  source_buf = nil
  source_win = nil
  source_to_preview = {}
  preview_to_source = {}
  is_syncing = false
  last_synced_s_top = nil
  last_synced_s_cursor = nil
  last_synced_p_top = nil
  last_synced_p_cursor = nil

  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    pcall(vim.api.nvim_set_current_win, prev_win)
  end
  if win_to_close and vim.api.nvim_win_is_valid(win_to_close) then
    pcall(vim.api.nvim_win_close, win_to_close, true)
  end
  if buf_to_delete and vim.api.nvim_buf_is_valid(buf_to_delete) then
    pcall(vim.api.nvim_buf_delete, buf_to_delete, { force = true })
  end
  if prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then
    pcall(function()
      require("super-markdown.render").render(prev_buf)
    end)
  end
end

function M.open(opts)
  opts = opts or {}
  if M.is_open() then
    M.refresh()
    return
  end

  source_buf = opts.bufnr or vim.api.nvim_get_current_buf()
  source_win = vim.api.nvim_get_current_win()

  local p_opts = (config.options and config.options.preview_pane) or {}
  local pos = opts.position or p_opts.position or "right"
  local width_cfg = opts.width or p_opts.width or 0.5
  local total_cols = vim.o.columns
  local width = (width_cfg <= 1) and math.floor(total_cols * width_cfg) or math.floor(width_cfg)
  width = math.max(40, width)

  local split_cmd = (pos == "left")
    and ("topleft vertical " .. width .. " split")
    or ("botright vertical " .. width .. " split")
  vim.cmd(split_cmd)

  preview_win = vim.api.nvim_get_current_win()
  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(preview_win, preview_buf)

  -- Configure read-only preview window appearance
  pcall(vim.api.nvim_set_option_value, "number", false, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", "0", { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "statuscolumn", "", { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "foldenable", false, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "foldmethod", "manual", { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "wrap", p_opts.wrap == true, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "conceallevel", 2, { win = preview_win })
  pcall(vim.api.nvim_set_option_value, "concealcursor", "nvic", { win = preview_win })
  update_winbar()

  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].swapfile = false
  vim.bo[preview_buf].filetype = "supermarkdown_preview"

  -- Keymaps inside the read-only preview pane
  local function bind_preview_keys()
    if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then
      return
    end
    local function bmap(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, {
        buffer = preview_buf,
        nowait = true,
        silent = true,
        noremap = true,
        desc = desc,
      })
    end
    bmap("n", "q", M.close, "Close Live Preview Pane")
    bmap("n", "Q", M.close, "Close Live Preview Pane")
    bmap("n", "<Esc>", M.close, "Close Live Preview Pane")
    bmap("n", "r", M.refresh, "Refresh Live Preview Pane")
    bmap("n", "m", "<Nop>", "Disable accidental mark creation in Preview Pane")
    local toggle_lhs = config.options and config.options.keymaps and config.options.keymaps.preview_pane
    if toggle_lhs and toggle_lhs ~= "" then
      bmap("n", toggle_lhs, M.toggle, "Toggle Live Preview Pane")
    end
    bmap("n", "s", function()
      M.set_sync("cycle")
    end, "Cycle Scroll Sync Mode (Both / Source→Preview / Preview→Source / Off)")
    bmap("n", "<CR>", function()
      M.jump_to_source()
    end, "Jump to Editable Source Buffer")
    bmap({ "n", "v", "x", "s" }, "<2-LeftMouse>", function()
      local mode = vim.api.nvim_get_mode().mode
      if mode:match("^[vVsS\22\19]") then
        vim.cmd("normal! \27")
      end
      local mouse = vim.fn.getmousepos()
      if mouse and mouse.winid == preview_win and mouse.line >= 1 then
        pcall(vim.api.nvim_win_set_cursor, preview_win, { mouse.line, math.max(0, (mouse.column or 1) - 1) })
      end
      M.jump_to_source()
    end, "Double-Click Jump to Editable Source Buffer")
    bmap("n", "gx", function()
      local p_line = vim.api.nvim_win_get_cursor(preview_win)[1]
      local s_line = map_preview_to_source(p_line)
      local s_win = resolve_source_win()
      if s_line and s_win and source_buf and vim.api.nvim_buf_is_valid(source_buf) then
        local ref = link_tool.get_reference_at(source_buf, s_line, 0)
        if ref then
          vim.api.nvim_set_current_win(s_win)
          pcall(vim.api.nvim_win_set_cursor, s_win, { s_line, 0 })
          link_tool.follow()
        end
      end
    end, "Follow Link in Source Line")
  end

  bind_preview_keys()

  -- Return focus to editor window if configured (default: keep focus in editor so user can keep typing)
  if opts.focus_preview ~= true and p_opts.focus_on_open ~= true then
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    end
  end

  M.refresh()
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    pcall(function()
      require("super-markdown.render").render(source_buf)
    end)
  end

  -- Attach bidirectional live-sync autocommands on source and preview buffers/windows
  augroup_id = vim.api.nvim_create_augroup("SuperMarkdownPreviewPane_" .. source_buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = augroup_id,
    buffer = source_buf,
    callback = function()
      M.debounced_refresh()
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup_id,
    buffer = source_buf,
    callback = function()
      if vim.api.nvim_get_current_win() ~= preview_win then
        M.sync_from_source()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup_id,
    buffer = preview_buf,
    callback = function()
      if vim.api.nvim_get_current_win() == preview_win then
        M.sync_from_preview()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = augroup_id,
    buffer = preview_buf,
    callback = function()
      bind_preview_keys()
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup_id,
    callback = function()
      if is_syncing or not M.is_open() then
        return
      end
      if vim.api.nvim_get_current_win() == preview_win then
        M.sync_from_preview()
      else
        M.sync_from_source()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = augroup_id,
    callback = function()
      M.debounced_refresh()
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = augroup_id,
    buffer = source_buf,
    callback = function()
      M.close()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup_id,
    pattern = tostring(preview_win),
    callback = function()
      preview_win = nil
      preview_buf = nil
    end,
  })
end

function M.toggle(opts)
  if M.is_open() then
    M.close()
    vim.notify("SuperMarkdown: Live Preview Pane Closed 󰄱", vim.log.levels.INFO)
  else
    M.open(opts)
    vim.notify("SuperMarkdown: Live Preview Pane Opened 󰄵", vim.log.levels.INFO)
  end
end

return M
