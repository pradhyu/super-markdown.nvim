local M = {}

local BDD_KEYWORDS = {
  { key = "Given", icon = "󰄱 Given ", hl = "SuperMarkdownBddGiven" },
  { key = "When",  icon = "󰄱 When ",  hl = "SuperMarkdownBddWhen" },
  { key = "Then",  icon = "󰄵 Then ",  hl = "SuperMarkdownBddThen" },
  { key = "And",   icon = "  ↳ And ", hl = "SuperMarkdownBddAnd" },
  { key = "But",   icon = "  ↳ But ", hl = "SuperMarkdownBddAnd" },
}

--- Render BDD keywords and Acceptance Criteria badges on a line
--- @param bufnr number
--- @param ns_id number
--- @param lnum number (0-indexed)
--- @param line string
--- @param opts table|nil
--- @return boolean matched
function M.render(bufnr, ns_id, lnum, line, opts)
  if opts and opts.enabled == false then return false end

  -- 1. Scenario / Acceptance Criteria header line
  local scen_match = line:match("^%s*#*%s*([Ss]cenario[^:]-:)%s*(.*)$")
  if scen_match then
    local s, e = line:find(scen_match, 1, true)
    if s then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        conceal = "",
        virt_text = { { "󰈙 " .. scen_match .. " ", "SuperMarkdownH3" } },
        virt_text_pos = "inline",
        priority = 98,
      })
      return true
    end
  end

  local ac_header = line:match("^%s*#*%s*([Aa]cceptance%s+[Cc]riteria%s*:)%s*(.*)$")
  if ac_header then
    local s, e = line:find(ac_header, 1, true)
    if s then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        conceal = "",
        virt_text = { { "󰄵 " .. ac_header .. " ", "SuperMarkdownH2" } },
        virt_text_pos = "inline",
        priority = 98,
      })
      return true
    end
  end

  -- 2. Given / When / Then / And / But step lines
  for _, item in ipairs(BDD_KEYWORDS) do
    local pattern = "^(%s*[%-%*%+]?%s*)(" .. item.key .. ")%s+(.*)$"
    local prefix, kw, _ = line:match(pattern)
    if prefix and kw then
      local s = #prefix + 1
      local e = s + #kw
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        conceal = "",
        virt_text = { { item.icon, item.hl } },
        virt_text_pos = "inline",
        priority = 98,
      })
      return true
    end
  end

  -- 3. Acceptance criteria code IDs: e.g. AC-01, AC-12
  local ac_s, ac_e, ac_id = line:find("%f[%a](AC%-%d+)%f[%A]")
  if ac_s and ac_id then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, ac_s - 1, {
      end_col = ac_e,
      hl_group = "SuperMarkdownSpecReqId",
      priority = 100,
    })
  end

  return false
end

--- Find all BDD scenarios and acceptance criteria in a buffer
--- @param bufnr? number
--- @return table[] scenarios { lnum, line, text, kind }
function M.find_scenarios(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}
  local in_fence = false

  for idx, l in ipairs(lines) do
    if l:match("^%s*```") or l:match("^%s*~~~") then
      in_fence = not in_fence
    elseif not in_fence then
      if l:match("^%s*#*%s*[Ss]cenario") then
        table.insert(results, { lnum = idx, line = l, kind = "scenario", text = vim.trim(l) })
      elseif l:match("%f[%a]AC%-%d+") then
        table.insert(results, { lnum = idx, line = l, kind = "ac", text = vim.trim(l) })
      elseif l:match("^%s*[%-%*%+]?%s*[Gg]iven%s") then
        table.insert(results, { lnum = idx, line = l, kind = "bdd_step", text = vim.trim(l) })
      end
    end
  end

  return results
end

return M
