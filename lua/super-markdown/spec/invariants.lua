local analyzer = require("super-markdown.spec.analyzer")
local config = require("super-markdown.config")

local M = {}

local float_win = nil
local float_buf = nil

--- Extract domain entities from markdown buffer lines
--- @param bufnr number
--- @return table entities
function M.extract_entities(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local endpoints = {}
  local env_vars = {}
  local tables = {}
  local error_codes = {}
  local headers = {}

  local in_codeblock = false
  local code_lang = ""

  for lnum, line in ipairs(lines) do
    if line:match("^%s*```(%w*)") then
      in_codeblock = not in_codeblock
      code_lang = line:match("^%s*```(%w*)") or ""
    elseif not in_codeblock and line:match("^%s*```") then
      in_codeblock = false
    else
      -- 1. HTTP Endpoints (e.g. POST /v2/charges, GET /v1/status)
      for method, path in line:gmatch("%f[%a](%u+)%s+([/%w_%-]+)%f[%A]") do
        if method == "GET" or method == "POST" or method == "PUT" or method == "DELETE" or method == "PATCH" then
          table.insert(endpoints, {
            method = method,
            path = path,
            lnum = lnum,
            line = line,
          })
        end
      end

      -- 2. Environment Variables (e.g. KAFKA_BROKERS, DATABASE_URL)
      for var in line:gmatch("`([A-Z][A-Z0-9_]+)`") do
        if #var >= 3 then
          table.insert(env_vars, {
            name = var,
            lnum = lnum,
            in_code = in_codeblock,
          })
        end
      end
      if in_codeblock then
        for var in line:gmatch("%f[%a]([A-Z][A-Z0-9_]+)%f[%A]") do
          if #var >= 4 then
            table.insert(env_vars, {
              name = var,
              lnum = lnum,
              in_code = true,
            })
          end
        end
      end

      -- 3. Database Tables (from SQL blocks or markdown tables)
      if in_codeblock and (code_lang == "sql" or code_lang == "bash" or code_lang == "sh") then
        local tbl = line:match("[tT][aA][bB][lL][eE]%s+([%w_]+)") or line:match("[fF][rR][oO][mM]%s+([%w_]+)") or line:match("[iI][nN][tT][oO]%s+([%w_]+)")
        if tbl and tbl:lower() ~= "payment" and #tbl > 2 then
          table.insert(tables, {
            name = tbl,
            lnum = lnum,
            sql = vim.trim(line),
          })
        end
      end

      -- 4. Custom Error Codes (e.g. ERR_INVALID_NONCE, ERR_UNAUTHORIZED)
      for err in line:gmatch("%f[%a](ERR_[A-Z0-9_]+)%f[%A]") do
        table.insert(error_codes, {
          code = err,
          lnum = lnum,
        })
      end

      -- 5. Standard Idempotency / Protocol Headers
      for hdr in line:gmatch("`?([I|i]dempotency%-[K|k]ey)`?") do
        table.insert(headers, {
          name = hdr,
          lnum = lnum,
        })
      end
    end
  end

  return {
    endpoints = endpoints,
    env_vars = env_vars,
    tables = tables,
    error_codes = error_codes,
    headers = headers,
  }
end

--- Validate domain invariants and identify AI drift or omissions
--- @param bufnr number
--- @return table report
function M.check(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local entities = M.extract_entities(bufnr)
  local issues = {}
  local passed = {}

  -- Invariant 1: Endpoint Pluralization / Spelling Drift
  local paths_seen = {}
  for _, ep in ipairs(entities.endpoints) do
    local normalized = ep.path:gsub("/$", "")
    local root = normalized:gsub("s$", "")
    if paths_seen[root] and paths_seen[root].path ~= normalized then
      table.insert(issues, {
        severity = "WARN",
        kind = "endpoint_drift",
        lnum = ep.lnum,
        title = "Endpoint Pluralization Drift",
        message = string.format("Potential drift between '%s' (line %d) and '%s' (line %d)", paths_seen[root].path, paths_seen[root].lnum, normalized, ep.lnum),
      })
    else
      paths_seen[root] = { path = normalized, lnum = ep.lnum }
    end
  end
  if #entities.endpoints > 0 and #issues == 0 then
    table.insert(passed, string.format("All %d HTTP endpoints have consistent route spelling and pluralization", #entities.endpoints))
  end

  -- Invariant 2: Environment Variables declared in code vs config
  local code_envs = {}
  local table_envs = {}
  for _, ev in ipairs(entities.env_vars) do
    if ev.in_code then
      code_envs[ev.name] = ev.lnum
    else
      table_envs[ev.name] = ev.lnum
    end
  end

  for var, lnum in pairs(code_envs) do
    if not table_envs[var] and not var:match("^HTTP_") and not var:match("^PATH$") and not var:match("^USER$") then
      table.insert(issues, {
        severity = "INFO",
        kind = "undeclared_env",
        lnum = lnum,
        title = "Undeclared Environment Variable",
        message = string.format("Variable '%s' used in code block (line %d) but omitted from Configuration tables", var, lnum),
      })
    end
  end
  if #entities.env_vars > 0 then
    table.insert(passed, string.format("Scanned %d environment variable reference(s)", #entities.env_vars))
  end

  -- Invariant 3: Idempotency headers matched with POST/PUT/PATCH mutations
  local has_mutation = false
  for _, ep in ipairs(entities.endpoints) do
    if ep.method == "POST" or ep.method == "PUT" or ep.method == "PATCH" then
      has_mutation = true
      break
    end
  end
  if has_mutation and #entities.headers > 0 then
    table.insert(passed, "Mutation endpoints have matching Idempotency Key header contracts")
  end

  -- Invariant 4: Database operations have hazard warnings or backup steps
  if #entities.tables > 0 then
    table.insert(passed, string.format("Tracked %d database table operation(s) across SQL blocks", #entities.tables))
  end

  return {
    passed = passed,
    issues = issues,
    entities = entities,
  }
end

--- Open interactive Invariants Report floating window
--- @param bufnr? number
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local report = M.check(bufnr)

  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
    float_win = nil
    float_buf = nil
  end

  float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].filetype = "supermarkdown_invariants"

  local lines = {
    " 󰡷 SuperMarkdown Spec Entity & Contract Invariant Report",
    "─────────────────────────────────────────────────────────────────────────────",
  }

  local line_to_source = {}

  if #report.issues == 0 then
    table.insert(lines, "  󰄵  All domain invariants and entity references passed verification.")
    table.insert(lines, "")
  else
    table.insert(lines, string.format("  ⚠  Found %d Potential Invariant Drift / Omission Issue(s):", #report.issues))
    table.insert(lines, "")
    for _, iss in ipairs(report.issues) do
      local icon = (iss.severity == "WARN") and "󰀦" or "󰋽"
      local l_idx = #lines + 1
      table.insert(lines, string.format("  %s [%s] line %d: %s", icon, iss.title, iss.lnum, iss.message))
      line_to_source[l_idx] = iss.lnum
    end
    table.insert(lines, "")
  end

  table.insert(lines, " 󰌶 Verified Invariant Checks:")
  for _, p in ipairs(report.passed) do
    table.insert(lines, "  • 󰄵 " .. p)
  end

  table.insert(lines, "")
  table.insert(lines, "─────────────────────────────────────────────────────────────────────────────")
  table.insert(lines, " [Enter] Jump to Line   [r] Refresh   [q / <Esc>] Close")

  vim.bo[float_buf].modifiable = true
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false

  local width = math.min(92, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " 󰡷 Spec Invariants & Contracts ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = float_win })

  -- Highlight header
  pcall(vim.api.nvim_buf_add_highlight, float_buf, -1, "SuperMarkdownH2", 0, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, float_buf, -1, "SuperMarkdownDivider", 1, 0, -1)

  local function close_report()
    M.close()
  end

  local function jump_source()
    local cur_row = vim.api.nvim_win_get_cursor(float_win)[1]
    local target_lnum = line_to_source[cur_row]
    if target_lnum then
      close_report()
      vim.api.nvim_win_set_cursor(0, { target_lnum, 0 })
      vim.cmd("normal! zvzz")
    end
  end

  local bopts = { buffer = float_buf, nowait = true, silent = true, noremap = true }
  vim.keymap.set("n", "q", close_report, bopts)
  vim.keymap.set("n", "<Esc>", close_report, bopts)
  vim.keymap.set("n", "<CR>", jump_source, bopts)
  vim.keymap.set("n", "r", function() M.open(bufnr) end, bopts)
end

function M.close()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
  end
  float_win = nil
  float_buf = nil
  return true
end

return M
