local config = require("super-markdown.config")

local M = {}

--- Resolved path or command to run termaid
local _cached_cmd = nil

--- Highlight mapping for termaid's styled-json tokens
local STYLE_MAP = {
  node = "SuperMarkdownTableBorder",
  edge = "SuperMarkdownMermaidArrow",
  arrow = "SuperMarkdownMermaidArrow",
  label = "SuperMarkdownMermaidNodeLabel",
  edge_label = "SuperMarkdownMermaidEdgeLabel",
  subgraph = "SuperMarkdownH3",
  default = "None",
}

--- Find the best command to invoke termaid
function M.get_command()
  if _cached_cmd then
    return _cached_cmd
  end

  local t_opts = (config.options.mermaid and config.options.mermaid.termaid) or {}
  local custom_cmd = t_opts.cmd or "termaid"

  -- 1. Check configured command
  if vim.fn.executable(custom_cmd) == 1 then
    _cached_cmd = { custom_cmd }
    return _cached_cmd
  end

  -- 2. Check ~/.local/bin/termaid
  local local_bin = vim.fn.expand("~/.local/bin/termaid")
  if vim.fn.executable(local_bin) == 1 then
    _cached_cmd = { local_bin }
    return _cached_cmd
  end

  -- 3. Check ~/.local/share/super-markdown/termaid-venv/bin/termaid
  local venv_bin = vim.fn.expand("~/.local/share/super-markdown/termaid-venv/bin/termaid")
  if vim.fn.executable(venv_bin) == 1 then
    _cached_cmd = { venv_bin }
    return _cached_cmd
  end

  -- 4. Check python3 -m termaid
  if vim.fn.executable("python3") == 1 then
    local test = vim.system({ "python3", "-m", "termaid", "--version" }):wait(1500)
    if test.code == 0 then
      _cached_cmd = { "python3", "-m", "termaid" }
      return _cached_cmd
    end
  end

  -- Fallback to default name
  return { custom_cmd }
end

--- Clear cached command (e.g. after install or config change)
function M.clear_cache()
  _cached_cmd = nil
end

--- Check if termaid is installed and executable
function M.is_available()
  local cmd_tbl = M.get_command()
  local first = cmd_tbl[1]
  if #cmd_tbl == 1 then
    return vim.fn.executable(first) == 1
  else
    local res = vim.system({ unpack(cmd_tbl), "--version" }):wait(1500)
    return res.code == 0
  end
end

--- Convert termaid styled-json chunk style string to Neovim highlight group
local function style_to_hl(style)
  if not style or style == "" then
    return "None"
  end
  if STYLE_MAP[style] then
    return STYLE_MAP[style]
  end
  if style:match("^class:") or style:match("^nodestyle:") then
    return "SuperMarkdownMermaidNodeLabel"
  elseif style:match("^linkstyle:") then
    return "SuperMarkdownMermaidArrow"
  elseif style:match("^section:") then
    return "SuperMarkdownH3"
  elseif style:match("label") then
    return "SuperMarkdownMermaidNodeLabel"
  elseif style:match("edge") or style:match("arrow") then
    return "SuperMarkdownMermaidArrow"
  end
  return "SuperMarkdownTableBorder"
end

--- Render mermaid diagram code using termaid
--- @param mermaid_code string
--- @param opts table|nil
--- @return boolean ok, table result: { text_lines = table, virt_lines = table, is_styled = boolean }
function M.render(mermaid_code, opts)
  opts = opts or {}
  local t_opts = (config.options.mermaid and config.options.mermaid.termaid) or {}
  local cmd_tbl = M.get_command()

  local format = opts.format or t_opts.format or "styled-json"
  local args = {}
  for _, c in ipairs(cmd_tbl) do
    table.insert(args, c)
  end

  table.insert(args, "--format")
  table.insert(args, format)

  local arrow_style = opts.arrow_style or t_opts.arrow_style or "pointer"
  if arrow_style and arrow_style ~= "" then
    table.insert(args, "--arrow-style")
    table.insert(args, arrow_style)
  end

  local padding_x = opts.padding_x or t_opts.padding_x or 2
  table.insert(args, "--padding-x")
  table.insert(args, tostring(padding_x))

  local padding_y = opts.padding_y or t_opts.padding_y or 1
  table.insert(args, "--padding-y")
  table.insert(args, tostring(padding_y))

  local gap = opts.gap or t_opts.gap or 2
  table.insert(args, "--gap")
  table.insert(args, tostring(gap))

  local width = opts.width or t_opts.width or opts.max_width
  if width and tonumber(width) and tonumber(width) > 20 then
    table.insert(args, "--width")
    table.insert(args, tostring(width))
  end

  if opts.ascii or t_opts.ascii then
    table.insert(args, "--ascii")
  end

  local theme = opts.theme or t_opts.theme
  if theme and theme ~= "" and format == "text" then
    table.insert(args, "--theme")
    table.insert(args, theme)
  end

  local res = vim.system(args, { stdin = mermaid_code }):wait(3500)
  if res.code ~= 0 or not res.stdout or res.stdout == "" then
    return false, {
      error = res.stderr or "termaid returned non-zero status " .. tostring(res.code),
    }
  end

  if format == "styled-json" then
    local ok_decode, data = pcall(vim.json.decode, res.stdout)
    if not ok_decode or not data or not data.lines then
      return false, { error = "Failed to parse termaid JSON output: " .. tostring(data) }
    end

    local virt_lines = {}
    local text_lines = {}

    for _, row in ipairs(data.lines) do
      local virt_row = {}
      local text_parts = {}
      for _, chunk in ipairs(row) do
        local txt = chunk.text or ""
        local hl = style_to_hl(chunk.style)
        table.insert(virt_row, { txt, hl })
        table.insert(text_parts, txt)
      end
      table.insert(virt_lines, virt_row)
      table.insert(text_lines, table.concat(text_parts))
    end

    return true, {
      virt_lines = virt_lines,
      text_lines = text_lines,
      is_styled = true,
      raw_json = data,
    }
  else
    -- Plain text output
    local text_lines = vim.split(res.stdout:gsub("\r\n", "\n"), "\n")
    -- Strip trailing empty lines
    while #text_lines > 0 and text_lines[#text_lines] == "" do
      table.remove(text_lines)
    end

    local ascii_mod = require("super-markdown.mermaid.ascii")
    local virt_lines = {}
    for _, line in ipairs(text_lines) do
      if ascii_mod.tokenize_line then
        table.insert(virt_lines, ascii_mod.tokenize_line(line))
      else
        table.insert(virt_lines, { { line, "SuperMarkdownTableBorder" } })
      end
    end

    return true, {
      virt_lines = virt_lines,
      text_lines = text_lines,
      is_styled = false,
    }
  end
end

return M
