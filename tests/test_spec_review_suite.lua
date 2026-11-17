-- Headless test runner for SuperMarkdown Spec Review Suite
vim.opt.runtimepath:prepend(vim.fn.expand("~/git/super-markdown.nvim"))
local function add_plugin(path)
  local p = vim.fn.expand(path)
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:append(p)
    package.path = package.path .. ";" .. p .. "/lua/?.lua;" .. p .. "/lua/?/init.lua"
  end
end
add_plugin("~/.local/share/nvim/lazy/plenary.nvim")
add_plugin("~/.local/share/nvim/lazy/telescope.nvim")

local sm = require("super-markdown")
sm.setup({})
vim.cmd("runtime! plugin/super-markdown.lua")

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("  FAIL: %s (expected %s, got %s)", msg or "", vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(val, msg)
  if val then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("  FAIL: %s (expected truthy, got %s)", msg or "", vim.inspect(val)))
  end
end

print("=== Running super-markdown.nvim Human Spec Review Suite ===")

-- 1. Test Ambiguity & Happy-Path Bias Spec Linter
print("\n[Test 1] Ambiguity & Happy-Path Bias Linter")
local sample_spec = {
  "# Payment Gateway V2 Specification",
  "",
  "## 1. Overview",
  "The system should be fast and offer high throughput with low latency and minimal overhead.",
  "It will follow industry standard practices and handle errors gracefully.",
  "",
  "## 2. API Endpoints",
  "### POST /v2/charges",
  "Creates a charge. Returns 200 OK or 201 Created.",
  "",
  "### GET /v2/charges/:id",
  "Fetches charge details. Returns 200 OK or 404 Not Found.",
}
local spec_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(spec_buf, 0, -1, false, sample_spec)

local analyzer = require("super-markdown.spec.analyzer")
local diagnostics = analyzer.lint(spec_buf)

local found_slop = {}
local happy_path_flagged = false
for _, diag in ipairs(diagnostics) do
  if diag.kind == "ambiguity" then
    table.insert(found_slop, diag.message)
  end
  if diag.message:match("Happy%-Path Bias") then
    happy_path_flagged = true
  end
end

assert_true(#found_slop >= 4, "Flagged untestable slop/ambiguity phrases (got " .. #found_slop .. ")")
assert_true(happy_path_flagged, "Flagged Happy-Path bias for POST /v2/charges (missing 4xx/5xx error contracts)")

-- 2. Test Spec Invariant & Entity Drift Checker
print("\n[Test 2] Spec Entity & Contract Invariant Validator")
local drift_spec = {
  "# Distributed Ledger Specification",
  "",
  "## 1. Endpoints",
  "POST /v2/transfers",
  "GET /v2/transfer",
  "",
  "## 2. Configuration",
  "| Variable | Description |",
  "| :--- | :--- |",
  "| `KAFKA_BROKERS` | Kafka bootstrap brokers |",
  "",
  "## 3. Worker Implementation",
  "```go",
  "brokers := os.Getenv(\"KAFKA_BROKERS\")",
  "secret := os.Getenv(\"DATABASE_PASSWORD_SECRET\")",
  "```",
  "",
  "## 4. Database Schema",
  "```sql",
  "CREATE TABLE settlement_ledger (id INT PRIMARY KEY);",
  "```",
}
local drift_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(drift_buf, 0, -1, false, drift_spec)

local invariants = require("super-markdown.spec.invariants")
local inv_report = invariants.check(drift_buf)

local found_endpoint_drift = false
local found_undeclared_env = false
for _, iss in ipairs(inv_report.issues) do
  if iss.kind == "endpoint_drift" then
    found_endpoint_drift = true
  elseif iss.kind == "undeclared_env" and iss.message:match("DATABASE_PASSWORD_SECRET") then
    found_undeclared_env = true
  end
end

assert_true(found_endpoint_drift, "Detected route pluralization drift (/v2/transfers vs /v2/transfer)")
assert_true(found_undeclared_env, "Detected undeclared environment variable DATABASE_PASSWORD_SECRET")
assert_true(#inv_report.entities.tables > 0, "Extracted database table settlement_ledger")

-- Test opening and closing the floating invariant window
vim.api.nvim_set_current_buf(drift_buf)
invariants.open(drift_buf)
assert_true(invariants.close(), "Invariants window opened and closed cleanly")

-- 3. Test Bidirectional Requirement-to-Code Traceability Matrix
print("\n[Test 3] Bidirectional Traceability Matrix")
local req_spec = {
  "# Auth Specification",
  "",
  "## 1. Requirements",
  "**REQ-01**: Secure Token Minting",
  "Tokens must expire after 15 minutes.",
  "@impl: lua/super-markdown/init.lua:10",
  "@test: tests/run_all.lua:20",
  "",
  "**REQ-02**: Refresh Token Rotation",
  "Refresh tokens are single-use.",
  "@impl: lua/super-markdown/config.lua:5",
  "",
  "**REQ-03**: Revocation Blacklist",
  "Revoked tokens must reject immediately.",
}
local req_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(req_buf, 0, -1, false, req_spec)

local traceability = require("super-markdown.spec.traceability")
local trace_report = traceability.compute(req_buf)

assert_eq(#trace_report.reqs, 3, "Parsed exactly 3 requirements")
assert_true(trace_report.impl_pct > 60 and trace_report.impl_pct < 70, "Impl coverage ~66.7% (2 of 3)")
assert_true(trace_report.test_pct > 30 and trace_report.test_pct < 40, "Test coverage ~33.3% (1 of 3)")

-- Test opening and closing the floating traceability window
vim.api.nvim_set_current_buf(req_buf)
traceability.open(req_buf)
assert_true(traceability.close(), "Traceability matrix window opened and closed cleanly")

-- 4. Test Interactive Spec Review Cockpit
print("\n[Test 4] Interactive Spec Review Cockpit HUD")
local review_spec = {
  "# Microservice Specification",
  "",
  "## 1. Architecture Overview",
  "- [x] Design data models",
  "- [ ] Define RPC contracts",
  "",
  "## 2. Failure Domain",
  "- [ ] Implement circuit breaker",
  "> [!IMPORTANT] Circuit breaker must trip at 50% errors.",
}
local r_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(r_buf, 0, -1, false, review_spec)
vim.api.nvim_set_current_buf(r_buf)

local review_session = require("super-markdown.spec.review_session")
review_session.start(r_buf)

-- Advance to next section, approve it
review_session.next()
review_session.approve()
assert_eq(review_session.get_current_section().review_status, "APPROVED", "Approved current section via review cockpit")

-- Advance to second section, reject with reason
review_session.next()
review_session.reject("Specify circuit breaker fallback semantics")
assert_eq(review_session.get_current_section().review_status, "REJECTED", "Rejected section with explicit reason")

-- Close cockpit
assert_true(review_session.close(), "Review cockpit closed cleanly")

-- 5. Test AI Re-Prompt Studio Action Plan Exporter
print("\n[Test 5] AI Re-Prompt Studio Action Plan Exporter")
local spec_init = require("super-markdown.spec")
local exported_prompt = spec_init.export_prompt(r_buf)

assert_true(type(exported_prompt) == "string", "Export prompt returns markdown string")
assert_true(exported_prompt:match("Specification Review") ~= nil, "Contains revision directives header")
assert_true(exported_prompt:match("Specify circuit breaker fallback semantics") ~= nil, "Contains recorded rejection reason")

-- 6. Test Neovim User Subcommands Integration
print("\n[Test 6] User Subcommands Execution")
vim.api.nvim_set_current_buf(r_buf)
local ok_cmd_inv, _ = pcall(vim.cmd, "SuperMarkdown invariants")
assert_true(ok_cmd_inv, ":SuperMarkdown invariants executed")
invariants.close()

local ok_cmd_tr, _ = pcall(vim.cmd, "SuperMarkdown traceability")
assert_true(ok_cmd_tr, ":SuperMarkdown traceability executed")
traceability.close()

local ok_cmd_rs, _ = pcall(vim.cmd, "SuperMarkdown review_session")
assert_true(ok_cmd_rs, ":SuperMarkdown review_session executed")
review_session.close()

local ok_cmd_exp, _ = pcall(vim.cmd, "SuperMarkdown prompt_export")
assert_true(ok_cmd_exp, ":SuperMarkdown prompt_export executed")

print(string.format("\n=== Spec Review Suite: %d Passed, %d Failed ===", passed, failed))
if failed > 0 then
  os.exit(1)
end
