local M = {}

M.PATTERNS = {
  { pattern = "%f[%a][Cc]ertainly[!,%.]?%f[%A]", label = "Conversational filler ('Certainly!')" },
  { pattern = "%f[%a][Aa]s an [Aa][Ii] language model%f[%A]", label = "AI disclaimer ('As an AI language model')" },
  { pattern = "%f[%a][Ww]ithout further ado%f[%A]", label = "Boilerplate preamble ('Without further ado')" },
  { pattern = "%f[%a][Ll]et'?s dive in[!]?%f[%A]", label = "Conversational filler ('Let's dive in')" },
  { pattern = "%f[%a][Ll]et'?s break this down[!]?%f[%A]", label = "Conversational filler ('Let's break this down')" },
  { pattern = "%f[%a][Hh]ere is the [^:\n]+:", label = "Generic presentation preamble ('Here is the...:')" },
  { pattern = "%f[%a][Ii]t is important to note that%f[%A]", label = "Filler phrase ('It is important to note that')" },
  { pattern = "%f[%a][Ii]t'?s worth noting that%f[%A]", label = "Filler phrase ('It's worth noting that')" },
  { pattern = "%f[%a][Aa]s mentioned previously%f[%A]", label = "Redundant repetition ('As mentioned previously')" },
  { pattern = "%f[%a][Aa]s mentioned above%f[%A]", label = "Redundant repetition ('As mentioned above')" },
  { pattern = "%f[%a][Ff]eel free to%f[%A]", label = "Chatbot politeness ('Feel free to...')" },
  { pattern = "%f[%a][Hh]ope this helps[!]?%f[%A]", label = "Chatbot sign-off ('Hope this helps!')" },
  { pattern = "%f[%a][Ll]et me know if you%f[%A]", label = "Chatbot sign-off ('Let me know if you need...')" },
  { pattern = "%f[%a][Ii]n this section,? we will%f[%A]", label = "Passive intro fluff ('In this section we will...')" },
}

--- Render AI fluff decorations on a line
--- @param bufnr number
--- @param ns_id number
--- @param lnum number (0-indexed)
--- @param line string
--- @param opts table|nil
--- @return boolean matched
function M.render(bufnr, ns_id, lnum, line, opts)
  if opts and opts.enabled == false then return false end

  for _, rule in ipairs(M.PATTERNS) do
    local s, e = line:find(rule.pattern)
    if s then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        hl_group = "SuperMarkdownAiFluff",
        virt_text = { { " 󰚩 AI Fluff", "SuperMarkdownAiFluffBadge" } },
        virt_text_pos = "eol",
        priority = 92,
      })
      return true
    end
  end

  return false
end

--- Find all lines containing AI fluff in a buffer
--- @param bufnr? number
--- @return table[] fluff_items { lnum, line, label }
function M.find_fluff(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}
  local in_fence = false

  for idx, l in ipairs(lines) do
    if l:match("^%s*```") or l:match("^%s*~~~") then
      in_fence = not in_fence
    elseif not in_fence then
      for _, rule in ipairs(M.PATTERNS) do
        local s, e = l:find(rule.pattern)
        if s then
          table.insert(results, {
            lnum = idx,
            line = l,
            start_col = s - 1,
            end_col = e,
            label = rule.label,
          })
          break
        end
      end
    end
  end

  return results
end

return M
