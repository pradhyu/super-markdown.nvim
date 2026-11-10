local M = {}

M.RULES = {
  -- 1. Destructive commands
  {
    pattern = "rm%s+%-[rf]*f[rf]*%s+",
    kind = "destructive",
    label = "Destructive recursive delete ('rm -rf')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "[Dd][Rr][Oo][Pp]%s+[Tt][Aa][Bb][Ll][Ee]",
    kind = "destructive",
    label = "Destructive table drop ('DROP TABLE')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "[Dd][Rr][Oo][Pp]%s+[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]",
    kind = "destructive",
    label = "Destructive database drop ('DROP DATABASE')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]%s+[%w_]+",
    kind = "destructive",
    label = "Destructive truncate operation ('TRUNCATE')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "git%s+push%s+.*%-%-force",
    kind = "destructive",
    label = "Destructive force push ('git push --force')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "git%s+reset%s+%-%-hard",
    kind = "destructive",
    label = "Destructive hard reset ('git reset --hard')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "kill%s+%-9",
    kind = "destructive",
    label = "Unconditional SIGKILL ('kill -9')",
    badge = "󰳦 DESTRUCTIVE OP",
    hl = "SuperMarkdownRiskHigh",
  },

  -- 2. Security sensitive
  {
    pattern = "chmod%s+777",
    kind = "security",
    label = "Insecure broad permissions ('chmod 777')",
    badge = "󰌾 SECURITY SENSITIVE",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "password%s*[:=]%s*['\"][^'\"]+['\"]",
    kind = "security",
    label = "Hardcoded password or secret detected",
    badge = "󰌾 HARDCODED SECRET",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "api_key%s*[:=]%s*['\"][^'\"]+['\"]",
    kind = "security",
    label = "Hardcoded API key detected",
    badge = "󰌾 HARDCODED SECRET",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "secret%s*[:=]%s*['\"][^'\"]+['\"]",
    kind = "security",
    label = "Hardcoded secret detected",
    badge = "󰌾 HARDCODED SECRET",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "token%s*[:=]%s*['\"][^'\"]+['\"]",
    kind = "security",
    label = "Hardcoded token detected",
    badge = "󰌾 HARDCODED SECRET",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "disable%s+auth",
    kind = "security",
    label = "Authentication bypass / disabled auth",
    badge = "󰌾 SECURITY RISK",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "unauthenticated",
    kind = "security",
    label = "Unauthenticated access vector",
    badge = "󰌾 SECURITY RISK",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "verify%s*=%s*[Ff]alse",
    kind = "security",
    label = "TLS certificate validation disabled ('verify=False')",
    badge = "󰌾 INSECURE TLS",
    hl = "SuperMarkdownRiskSec",
  },
  {
    pattern = "%-%-no%-check%-certificate",
    kind = "security",
    label = "TLS validation bypass ('--no-check-certificate')",
    badge = "󰌾 INSECURE TLS",
    hl = "SuperMarkdownRiskSec",
  },

  -- 3. Breaking changes & migrations
  {
    pattern = "BREAKING%s+CHANGE",
    kind = "breaking",
    label = "Breaking change declared",
    badge = "󰀦 BREAKING CHANGE",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "BREAKING:",
    kind = "breaking",
    label = "Breaking change declared",
    badge = "󰀦 BREAKING CHANGE",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "backward%s+incompatible",
    kind = "breaking",
    label = "Backward-incompatible change",
    badge = "󰀦 BREAKING CHANGE",
    hl = "SuperMarkdownRiskHigh",
  },
  {
    pattern = "schema%s+migration",
    kind = "migration",
    label = "Database or schema migration",
    badge = "󰆼 SCHEMA MIGRATION",
    hl = "SuperMarkdownRiskSec",
  },
}

--- Render risk badges and indicators on a line
--- @param bufnr number
--- @param ns_id number
--- @param lnum number (0-indexed)
--- @param line string
--- @param opts table|nil
--- @return boolean matched
function M.render(bufnr, ns_id, lnum, line, opts)
  if opts and opts.enabled == false then return false end

  for _, rule in ipairs(M.RULES) do
    local s, e = line:find(rule.pattern)
    if s then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        hl_group = rule.hl,
        virt_text = { { "  " .. rule.badge, rule.hl } },
        virt_text_pos = "eol",
        priority = 106,
      })
      return true
    end
  end

  return false
end

--- Find all risks in a buffer for linter, navigation, and HUD
--- @param bufnr? number
--- @return table[] risks { lnum, line, kind, label, badge, hl }
function M.find_risks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}

  for idx, l in ipairs(lines) do
    for _, rule in ipairs(M.RULES) do
      local s, e = l:find(rule.pattern)
      if s then
        table.insert(results, {
          lnum = idx,
          line = l,
          start_col = s - 1,
          end_col = e,
          kind = rule.kind,
          label = rule.label,
          badge = rule.badge,
          hl = rule.hl,
        })
        break
      end
    end
  end

  return results
end

return M
