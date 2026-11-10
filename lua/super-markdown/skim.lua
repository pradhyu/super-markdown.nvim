local config = require("super-markdown.config")

local M = {}

local NS_SKIM = vim.api.nvim_create_namespace("super_markdown_skim")
local skim_states = {} -- bufnr -> bool

--- Check if line is a structural element that should remain prominent during Skim Mode
--- @param line string
--- @param in_codeblock boolean
--- @return boolean is_structural
local function is_structural_line(line, in_codeblock)
  if in_codeblock then return true end
  if line:match("^%s*$") then return true end

  -- Headings
  if line:match("^%s*#+%s") then return true end

  -- Code fences
  if line:match("^%s*```") or line:match("^%s*~~~") then return true end

  -- Tables
  if line:match("^%s*|.*|%s*$") then return true end

  -- Checkboxes and list items
  if line:match("^%s*[%-%*%+]%s+%[.%]") or line:match("^%s*%d+%.%s+%[.%]") then return true end
  if line:match("^%s*[%-%*%+]%s+") or line:match("^%s*%d+%.%s+") then return true end

  -- Callouts and blockquotes
  if line:match("^%s*>") then return true end

  -- Dividers
  if line:match("^%s*[%-%*_][%s%-%*_]+$") and #line:gsub("%s+", "") >= 3 then return true end

  -- BDD keywords & Acceptance criteria
  if line:match("^%s*[Gg]iven%s") or line:match("^%s*[Ww]hen%s") or line:match("^%s*[Tt]hen%s")
    or line:match("^%s*[Aa]nd%s") or line:match("^%s*[Bb]ut%s")
    or line:match("^%s*[Ss]cenario") or line:match("%f[%a]AC%-%d+")
    or line:match("%f[%a]REQ%-%d+") then
    return true
  end

  -- Traceability tags
  if line:match("@impl:") or line:match("@test:") then return true end

  -- Frontmatter delimiters
  if line:match("^%-%-%-%s*$") or line:match("^%.%.%.%s*$") then return true end

  return false
end

--- Check if Skim Mode is active on buffer
--- @param bufnr? number
--- @return boolean
function M.is_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return skim_states[bufnr] == true
end

--- Clear Skim Mode extmarks
--- @param bufnr? number
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, NS_SKIM, 0, -1)
  end
end

--- Render Skim Mode decorations on buffer
--- @param bufnr? number
function M.render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if not M.is_enabled(bufnr) then
    M.clear(bufnr)
    return
  end

  M.clear(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local in_codeblock = false

  for idx, line in ipairs(lines) do
    local lnum = idx - 1
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_codeblock = not in_codeblock
    elseif not in_codeblock then
      if not is_structural_line(line, in_codeblock) then
        -- Non-structural paragraph prose: dim it significantly to highlight structural skeleton
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_SKIM, lnum, 0, {
          end_col = #line,
          hl_group = "SuperMarkdownSkimDimmed",
          line_hl_group = "SuperMarkdownSkimLine",
          priority = 110,
        })
      end
    end
  end
end

--- Enable Skim Mode on buffer
--- @param bufnr? number
function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  skim_states[bufnr] = true
  M.render(bufnr)
  vim.notify("SuperMarkdown: Skim Mode Enabled 󰄵 (Prose dimmed, structure highlighted)", vim.log.levels.INFO)
end

--- Disable Skim Mode on buffer
--- @param bufnr? number
function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  skim_states[bufnr] = false
  M.clear(bufnr)
  vim.notify("SuperMarkdown: Skim Mode Disabled 󰄱 (Normal view restored)", vim.log.levels.INFO)
end

--- Toggle Skim Mode on buffer
--- @param bufnr? number
--- @return boolean new_state
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
    return false
  else
    M.enable(bufnr)
    return true
  end
end

return M
