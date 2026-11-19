-- In-buffer shell command formatter for Markdown code blocks & selections.
-- Combine multi-line commands into one line, or split a single-line command
-- into multi-line with `\` (Bash/Zsh/Sh) or `` ` `` (PowerShell/pwsh).

local runner = require("super-markdown.tools.runner")

local M = {}

local PWSH_LANGS = {
  pwsh = true,
  powershell = true,
  ps1 = true,
  ps = true,
}

---Normalize a shell override or fence language into "bash" or "powershell"
---@param spec? string
---@return "bash"|"powershell"|nil
local function normalize_shell(spec)
  if not spec or spec == "" then
    return nil
  end
  local s = spec:lower()
  if PWSH_LANGS[s] or s == "`" or s == "backtick" then
    return "powershell"
  elseif s == "bash" or s == "sh" or s == "zsh" or s == "fish" or s == "shell" or s == "console" or s == "\\" or s == "backslash" then
    return "bash"
  end
  return nil
end

---Detect shell ("bash" or "powershell") from override, enclosing fence language, or lines
---@param bufnr integer
---@param lnum integer 1-indexed line
---@param lines string[]
---@param override? string
---@return "bash"|"powershell"
function M.detect_shell(bufnr, lnum, lines, override)
  local forced = normalize_shell(override)
  if forced then
    return forced
  end

  local block = runner.get_block_at_cursor(bufnr, lnum)
  if block and block.lang and block.lang ~= "" then
    local from_fence = normalize_shell(block.lang)
    if from_fence then
      return from_fence
    end
  end

  -- Fallback: inspect existing continuation characters in the lines
  for _, line in ipairs(lines or {}) do
    if line:match("`%s*$") then
      return "powershell"
    end
  end
  return "bash"
end

---Get the continuation character for a shell type
---@param shell "bash"|"powershell"
---@return string
function M.cont_char(shell)
  return shell == "powershell" and "`" or "\\"
end

---Resolve target 1-indexed line range (start_lnum, end_lnum) from explicit args,
---active visual selection, enclosing fenced code block, or current line.
---@param bufnr integer
---@param start_lnum? integer
---@param end_lnum? integer
---@return integer, integer
local function resolve_range(bufnr, start_lnum, end_lnum)
  if start_lnum and end_lnum then
    return math.min(start_lnum, end_lnum), math.max(start_lnum, end_lnum)
  end

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local l1 = vim.fn.line("v")
    local l2 = vim.fn.line(".")
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "n", false)
    return math.min(l1, l2), math.max(l1, l2)
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local block = runner.get_block_at_cursor(bufnr, cur)
  if block and block.end_lnum > block.start_lnum + 1 then
    return block.start_lnum + 1, block.end_lnum - 1
  end

  return cur, cur
end

---Tokenize a single shell command line while keeping quoted strings intact
---@param str string
---@return string[]
function M.tokenize(str)
  local tokens = {}
  local cur = {}
  local i = 1
  local n = #str
  local in_single = false
  local in_double = false

  while i <= n do
    local ch = str:sub(i, i)
    if in_single then
      table.insert(cur, ch)
      if ch == "'" then
        in_single = false
      end
    elseif in_double then
      table.insert(cur, ch)
      if ch == "\\" and i < n then
        i = i + 1
        table.insert(cur, str:sub(i, i))
      elseif ch == '"' then
        in_double = false
      end
    else
      if ch == "'" then
        in_single = true
        table.insert(cur, ch)
      elseif ch == '"' then
        in_double = true
        table.insert(cur, ch)
      elseif ch == "\\" and i < n and str:sub(i + 1, i + 1) == " " then
        table.insert(cur, "\\ ")
        i = i + 1
      elseif ch:match("%s") then
        if #cur > 0 then
          table.insert(tokens, table.concat(cur))
          cur = {}
        end
      else
        table.insert(cur, ch)
      end
    end
    i = i + 1
  end

  if #cur > 0 then
    table.insert(tokens, table.concat(cur))
  end
  return tokens
end

local function is_flag(tok)
  return tok:match("^%-%-?[%w]") ~= nil
end

local function is_operator(tok)
  return tok == "|" or tok == "&&" or tok == "||" or tok == ";"
end

---Split a single command line into logical multiline parts (pure function)
---@param line string
---@param shell "bash"|"powershell"
---@return string[]
function M.split_line_text(line, shell)
  local base_indent = line:match("^(%s*)") or ""
  local trimmed = vim.trim(line):gsub("%s*[`\\]%s*$", "")
  local tokens = M.tokenize(trimmed)
  if #tokens <= 1 then
    return { line }
  end

  local char = M.cont_char(shell)
  local cont_indent = base_indent .. "  "

  -- Group tokens into logical chunks:
  -- 1. Leading command + subcommand tokens until first flag/operator
  -- 2. Each flag + its immediate non-flag/non-operator argument (unless flag uses = or :)
  -- 3. Operators (|, &&, ||) start a new line
  local chunks = {}
  local cur_chunk = {}
  local seen_flag = false

  local i = 1
  while i <= #tokens do
    local tok = tokens[i]
    if is_operator(tok) then
      if #cur_chunk > 0 then
        table.insert(chunks, { text = table.concat(cur_chunk, " "), op_before = false })
        cur_chunk = {}
      end
      -- Attach operator to end of previous chunk if possible, else start new chunk
      if #chunks > 0 and (tok == "|" or tok == "&&" or tok == "||") then
        chunks[#chunks].text = chunks[#chunks].text .. " " .. tok
        chunks[#chunks].no_cont = true
      else
        table.insert(cur_chunk, tok)
      end
      seen_flag = false
      i = i + 1
    elseif is_flag(tok) then
      if #cur_chunk > 0 then
        table.insert(chunks, { text = table.concat(cur_chunk, " ") })
        cur_chunk = {}
      end
      seen_flag = true
      -- Pair flag with its immediate value argument if present and not another flag/operator
      local next_tok = tokens[i + 1]
      if next_tok and not is_flag(next_tok) and not is_operator(next_tok) and not tok:find("=", 1, true) then
        table.insert(chunks, { text = tok .. " " .. next_tok })
        i = i + 2
      else
        table.insert(chunks, { text = tok })
        i = i + 1
      end
    else
      if seen_flag then
        -- Positional argument after flags (e.g. URL at end of curl) gets its own line
        if #cur_chunk > 0 then
          table.insert(chunks, { text = table.concat(cur_chunk, " ") })
          cur_chunk = {}
        end
        table.insert(chunks, { text = tok })
      else
        table.insert(cur_chunk, tok)
      end
      i = i + 1
    end
  end

  if #cur_chunk > 0 then
    table.insert(chunks, { text = table.concat(cur_chunk, " ") })
  end

  -- If no flags/operators caused a split, fall back to splitting every token after the first
  if #chunks <= 1 then
    chunks = {}
    for _, tok in ipairs(tokens) do
      table.insert(chunks, { text = tok })
    end
  end

  local out = {}
  for idx, chunk in ipairs(chunks) do
    local indent = (idx == 1) and base_indent or cont_indent
    if idx < #chunks then
      if chunk.no_cont then
        table.insert(out, indent .. chunk.text)
      else
        table.insert(out, indent .. chunk.text .. " " .. char)
      end
    else
      table.insert(out, indent .. chunk.text)
    end
  end
  return out
end

---Combine lines into one single line (pure function)
---@param lines string[]
---@return string
function M.join_lines_text(lines)
  local base_indent = nil
  local parts = {}
  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then
      if not base_indent then
        base_indent = line:match("^(%s*)") or ""
      end
      local clean = vim.trim(line):gsub("%s*[`\\]%s*$", "")
      clean = vim.trim(clean)
      if clean ~= "" then
        table.insert(parts, clean)
      end
    end
  end
  return (base_indent or "") .. table.concat(parts, " ")
end

---Add or convert trailing continuation characters (`\` or `` ` ``) across multiple lines
---@param lines string[]
---@param shell "bash"|"powershell"
---@return string[]
function M.format_multiline_continuations(lines, shell)
  local char = M.cont_char(shell)
  local non_empty = {}
  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then
      table.insert(non_empty, line)
    end
  end
  if #non_empty == 0 then
    return lines
  end

  local out = {}
  for i, line in ipairs(non_empty) do
    local clean = line:gsub("%s*[`\\]%s*$", ""):gsub("%s+$", "")
    if i < #non_empty then
      if clean:match("|%s*$") or clean:match("&&%s*$") or clean:match("||%s*$") then
        table.insert(out, clean)
      else
        table.insert(out, clean .. " " .. char)
      end
    else
      table.insert(out, clean)
    end
  end
  return out
end

---Combine selected lines or current code block into one single line in-place
---@param bufnr? integer
---@param start_lnum? integer
---@param end_lnum? integer
function M.join_one_line(bufnr, start_lnum, end_lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.bo[bufnr].modifiable then
    return
  end
  local s, e = resolve_range(bufnr, start_lnum, end_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  local joined = M.join_lines_text(lines)
  vim.api.nvim_buf_set_lines(bufnr, s - 1, e, false, { joined })
  vim.notify("SuperMarkdown: Combined into one line", vim.log.levels.INFO)
end

---Split a single line into multiline (or convert continuation chars on multiline) in-place
---@param bufnr? integer
---@param start_lnum? integer
---@param end_lnum? integer
---@param shell_override? string
function M.split_multiline(bufnr, start_lnum, end_lnum, shell_override)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.bo[bufnr].modifiable then
    return
  end
  local s, e = resolve_range(bufnr, start_lnum, end_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  local shell = M.detect_shell(bufnr, s, lines, shell_override)

  local non_empty_count = 0
  local single_line = nil
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      non_empty_count = non_empty_count + 1
      single_line = l
    end
  end

  local result
  if non_empty_count <= 1 and single_line then
    result = M.split_line_text(single_line, shell)
  else
    result = M.format_multiline_continuations(lines, shell)
  end

  vim.api.nvim_buf_set_lines(bufnr, s - 1, e, false, result)
  vim.notify(
    string.format("SuperMarkdown: Formatted multiline (%s: %s)", shell, M.cont_char(shell)),
    vim.log.levels.INFO
  )
end

---Toggle between one-line and multiline (auto-detecting bash `\` vs powershell `` ` ``)
---@param bufnr? integer
---@param start_lnum? integer
---@param end_lnum? integer
---@param shell_override? string
function M.toggle_multiline(bufnr, start_lnum, end_lnum, shell_override)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.bo[bufnr].modifiable then
    return
  end
  local s, e = resolve_range(bufnr, start_lnum, end_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  local non_empty = 0
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      non_empty = non_empty + 1
    end
  end

  if non_empty > 1 then
    M.join_one_line(bufnr, s, e)
  else
    M.split_multiline(bufnr, s, e, shell_override)
  end
end

return M
