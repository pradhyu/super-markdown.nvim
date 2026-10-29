local M = {}

M.templates = {
  architecture = {
    name = "System Architecture & RFC Spec",
    desc = "Full system architecture spec with Mermaid topology, sequence flow, SLO routing table, and @impl/@test traceability",
    lines = {
      "# System Architecture Specification: [Component Name]",
      "",
      "> **Document Status**: `DRAFT`",
      "> **Version**: 1.0.0",
      "> **Owner**: @team",
      "> **Target Release**: Q4 2026",
      "",
      "---",
      "",
      "## 1. Overview & Goals",
      "",
      "Describe the core problem, architectural constraints, and non-goals for LLM context alignment.",
      "",
      "- **Primary Objective**: Deliver deterministic, observable handling of...",
      "- **Traceability**:",
      "  - `@impl: src/core/handler.lua`",
      "  - `@test: tests/core_spec.lua`",
      "",
      "> [!IMPORTANT]",
      "> All external inputs must be validated against schema contracts before state mutation.",
      "",
      "---",
      "",
      "## 2. Component Topology",
      "",
      "```mermaid",
      "graph TD",
      "    Client[Client Request] --> Gateway[API Gateway]",
      "    Gateway --> Validator{Schema Validator}",
      "    Validator -->|Valid| Service[Core Domain Service]",
      "    Validator -->|Invalid| Reject[400 Bad Request]",
      "    Service --> Store[(Primary Datastore)]",
      "```",
      "",
      "---",
      "",
      "## 3. Execution Sequence Flow",
      "",
      "```mermaid",
      "sequenceDiagram",
      "    autonumber",
      "    actor User as Caller",
      "    participant API as Handler",
      "    participant DB as Storage",
      "    User->>API: Submit Payload",
      "    API->>DB: Persist Record",
      "    DB-->>API: Ack (ID)",
      "    API-->>User: 200 OK",
      "```",
      "",
      "---",
      "",
      "## 4. Functional Requirements & SLO Matrix",
      "",
      "| Req ID | Requirement Description | Target SLO | Priority | Verification |",
      "| :--- | :--- | :---: | :---: | :--- |",
      "| REQ-01 | Validate request payload schema | < 5ms | P0 | Unit Test |",
      "| REQ-02 | Idempotent retry on transient failure | < 50ms | P0 | Integration Test |",
      "| REQ-03 | Emit structured audit log event | < 10ms | P1 | E2E Test |",
      "",
      "---",
      "",
      "## 5. Implementation & Test Checklist",
      "",
      "- [ ] Implement core domain module (`REQ-01`)",
      "- [ ] Add retry & error boundary handling (`REQ-02`)",
      "- [ ] Generate unit & integration test suite (`REQ-03`)",
      "- [?] Confirm rate-limiting burst threshold with platform team",
      "- [!] Ensure zero plaintext secrets in error logs",
    },
  },

  feature = {
    name = "Feature PRD & LLM Implementation Spec",
    desc = "Feature specification with acceptance criteria, data model, edge cases, and test generation prompts",
    lines = {
      "# Feature Specification: [Feature Title]",
      "",
      "> **Document Status**: `DRAFT`",
      "> **Version**: 0.1.0",
      "> **Owner**: @developer",
      "",
      "---",
      "",
      "## 1. Context & User Story",
      "",
      "As a **[user persona]**, I want **[capability]** so that **[measurable outcome]**.",
      "",
      "- `@impl: lua/module/feature.lua`",
      "- `@test: tests/feature_spec.lua`",
      "",
      "---",
      "",
      "## 2. Functional Requirements",
      "",
      "- **REQ-01**: Support primary happy-path workflow with deterministic output.",
      "- **REQ-02**: Reject malformed inputs with structured diagnostic messages.",
      "- **REQ-03**: Maintain backward compatibility with existing configuration.",
      "",
      "---",
      "",
      "## 3. Edge Cases & Error Matrix",
      "",
      "| Scenario | Input Condition | Expected Behavior | Error Code |",
      "| :--- | :--- | :--- | :---: |",
      "| Empty Input | `nil` or `\"\"` | Return no-op with warning | `ERR_EMPTY` |",
      "| Timeout | > 2000ms | Cancel job and notify caller | `ERR_TIMEOUT` |",
      "| Invalid Type | Non-table opts | Fallback to default config | `ERR_CONFIG` |",
      "",
      "---",
      "",
      "## 4. Acceptance Criteria & Tasks",
      "",
      "- [ ] Implement `REQ-01` core logic",
      "- [ ] Handle all edge cases from Section 3",
      "- [ ] Generate automated unit tests covering happy path & error matrix",
      "- [?] Should this feature be enabled by default in `config.lua`?",
    },
  },

  api = {
    name = "API Endpoint & Contract Spec",
    desc = "REST/RPC API contract spec with routes, request/response schemas, and test cases",
    lines = {
      "# API Specification: [Service / Endpoint]",
      "",
      "> **Document Status**: `DRAFT`",
      "> **Version**: 1.0.0",
      "",
      "---",
      "",
      "## 1. Endpoint Summary",
      "",
      "| Method | Route | Auth Scope | Rate Limit | Latency SLO |",
      "| :---: | :--- | :---: | :---: | ---: |",
      "| `POST` | `/api/v1/resource` | `write:resource` | 100 req/m | < 40ms |",
      "| `GET` | `/api/v1/resource/:id` | `read:resource` | 500 req/m | < 15ms |",
      "",
      "---",
      "",
      "## 2. Request & Response Payloads",
      "",
      "```json",
      "{",
      "  \"id\": \"res_12345\",",
      "  \"status\": \"active\",",
      "  \"created_at\": \"2026-10-29T00:00:00Z\"",
      "}",
      "```",
      "",
      "---",
      "",
      "## 3. Status Codes & Verification Checklist",
      "",
      "- [ ] `201 Created`: Valid payload persisted (`REQ-01`)",
      "- [ ] `400 Bad Request`: Missing required field (`REQ-02`)",
      "- [ ] `401 Unauthorized`: Invalid or expired bearer token (`REQ-03`)",
      "- [ ] `429 Too Many Requests`: Rate limit exceeded (`REQ-04`)",
    },
  },

  test_plan = {
    name = "Application Test Plan & Verification Spec",
    desc = "Structured test matrix for LLM test suite generation and inline verification",
    lines = {
      "# Application Test Plan: [Module / Feature]",
      "",
      "> **Document Status**: `APPROVED`",
      "> **Version**: 1.0.0",
      "",
      "---",
      "",
      "## 1. Test Scope & Traceability",
      "",
      "- **Target Implementation**: `@impl: lua/super-markdown/init.lua`",
      "- **Target Test Suite**: `@test: tests/run_all.lua`",
      "",
      "---",
      "",
      "## 2. Test Case Matrix",
      "",
      "| Test ID | Category | Target Function / Flow | Input Fixture | Expected Assertion |",
      "| :--- | :---: | :--- | :--- | :--- |",
      "| TC-01 | Unit | Parser initialization | Default config | Returns valid state table |",
      "| TC-02 | Boundary | Empty buffer input | `0` lines | Graceful no-op without error |",
      "| TC-03 | Integration | Full pipeline render | Markdown fixture | Populates extmarks & folds |",
      "",
      "---",
      "",
      "## 3. Executable Verification Snippet",
      "",
      "```lua",
      "print('Verification check: OK')",
      "```",
      "",
      "---",
      "",
      "## 4. Test Execution Checklist",
      "",
      "- [ ] Generate unit tests for `TC-01` and `TC-02`",
      "- [ ] Generate integration test for `TC-03`",
      "- [ ] Run test suite and verify 0 failures",
    },
  },
}

--- Insert a spec template into the current buffer (or create a new buffer if current buffer is non-empty and not markdown)
--- @param template_key string|nil
--- @param opts table|nil
function M.insert_template(template_key, opts)
  opts = opts or {}

  local function apply_template(key)
    local tpl = M.templates[key]
    if not tpl then
      vim.notify("SuperMarkdown: Unknown spec template '" .. tostring(key) .. "'", vim.log.levels.ERROR)
      return
    end

    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local is_empty = (#existing == 0) or (#existing == 1 and vim.trim(existing[1]) == "")

    if is_empty then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, tpl.lines)
      vim.bo[bufnr].filetype = "markdown"
    else
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local insert_lines = { "" }
      vim.list_extend(insert_lines, tpl.lines)
      vim.api.nvim_buf_set_lines(bufnr, row, row, false, insert_lines)
    end

    vim.notify("SuperMarkdown: Inserted '" .. tpl.name .. "' template 󰍔", vim.log.levels.INFO)
  end

  if template_key and M.templates[template_key] then
    apply_template(template_key)
    return
  end

  local keys = { "architecture", "feature", "api", "test_plan" }
  vim.ui.select(keys, {
    prompt = "Select Spec Template:",
    format_item = function(k)
      return string.format("%s — %s", M.templates[k].name, M.templates[k].desc)
    end,
  }, function(choice)
    if choice then
      apply_template(choice)
    end
  end)
end

--- Cycle the Document Status in frontmatter or top blockquote metadata
--- @param bufnr number|nil
function M.cycle_status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local states = { "DRAFT", "REVIEW", "APPROVED", "IN_PROGRESS", "IMPLEMENTED", "VERIFIED" }
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(30, vim.api.nvim_buf_line_count(bufnr)), false)

  for i, line in ipairs(lines) do
    -- Check blockquote status: > **Document Status**: `APPROVED`
    local prefix, cur, suffix = line:match("^(>%s*%*%*[^%*]*[sS]tatus[^%*]*%*%*%s*:%s*`?)([%w_%-]+)(`?%s*)$")
    if prefix and cur then
      local next_state = states[1]
      for idx, s in ipairs(states) do
        if s == cur:upper() then
          next_state = states[(idx % #states) + 1]
          break
        end
      end
      local new_line = prefix .. next_state .. suffix
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
      vim.notify("SuperMarkdown: Spec Status ➔ " .. next_state, vim.log.levels.INFO)
      return next_state
    end

    -- Check YAML frontmatter status: status: DRAFT
    local y_prefix, y_cur = line:match("^(%s*status%s*:%s*)([%w_%-]+)%s*$")
    if y_prefix and y_cur then
      local next_state = states[1]
      for idx, s in ipairs(states) do
        if s == y_cur:upper() then
          next_state = states[(idx % #states) + 1]
          break
        end
      end
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { y_prefix .. next_state })
      vim.notify("SuperMarkdown: Spec Status ➔ " .. next_state, vim.log.levels.INFO)
      return next_state
    end
  end

  -- If no status header exists yet, insert one beneath H1
  for i, line in ipairs(lines) do
    if line:match("^#%s+") then
      vim.api.nvim_buf_set_lines(bufnr, i, i, false, {
        "",
        "> **Document Status**: `DRAFT`",
      })
      vim.notify("SuperMarkdown: Added Spec Status header (`DRAFT`)", vim.log.levels.INFO)
      return "DRAFT"
    end
  end
end

return M
