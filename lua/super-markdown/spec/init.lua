local analyzer = require("super-markdown.spec.analyzer")
local templates = require("super-markdown.spec.templates")
local picker = require("super-markdown.spec.picker")

local M = {}

local dash_win = nil
local dash_buf = nil
local NS_DASH = vim.api.nvim_create_namespace("super_markdown_spec_dashboard")

M.analyze = analyzer.analyze
M.get_section_at = analyzer.get_section_at
M.resolve_reference = analyzer.resolve_reference
M.new_spec = templates.insert_template
M.cycle_status = templates.cycle_status
M.pick = picker.open

--- Run spec linter and notify user
--- @param bufnr number|nil
function M.lint(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local issues = analyzer.lint(bufnr, true)
  if #issues == 0 then
    vim.notify("SuperMarkdown Spec Linter: 0 issues found — spec is crisp and LLM-ready! 󰄵", vim.log.levels.INFO)
  else
    vim.notify(
      string.format("SuperMarkdown Spec Linter: %d issue(s) flagged (use ]d / [d to navigate)", #issues),
      vim.log.levels.WARN
    )
  end
  return issues
end

function M.clear_lint(bufnr)
  analyzer.clear_lint(bufnr)
  vim.notify("SuperMarkdown: Cleared spec lint diagnostics", vim.log.levels.INFO)
end

--- Render a visual progress bar string
--- @param done number
--- @param total number
--- @param width number
--- @return string
local function make_progress_bar(done, total, width)
  width = width or 20
  if total <= 0 then
    return string.rep("░", width) .. " 100% (0/0 tasks)"
  end
  local ratio = math.max(0, math.min(1, done / total))
  local filled = math.floor(ratio * width + 0.5)
  local empty = width - filled
  local pct = math.floor(ratio * 100 + 0.5)
  return string.format("%s%s %d%% (%d/%d tasks)", string.rep("█", filled), string.rep("░", empty), pct, done, total)
end

--- Close the Spec Health Dashboard if open
function M.close_dashboard()
  if dash_win and vim.api.nvim_win_is_valid(dash_win) then
    pcall(vim.api.nvim_win_close, dash_win, true)
  end
  dash_win = nil
  dash_buf = nil
end

--- Open interactive Spec Health & Traceability Dashboard floating window
--- @param bufnr number|nil
function M.dashboard(bufnr)
  if dash_win and vim.api.nvim_win_is_valid(dash_win) then
    M.close_dashboard()
    return
  end

  local source_buf = bufnr or vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local analysis = analyzer.analyze(source_buf)
  local lint_issues = analyzer.lint(source_buf, true)

  local meta = analysis.metadata
  local t = analysis.totals
  local lines = {}
  local line_targets = {} -- dashboard line_idx (1-based) -> source lnum

  local function add_line(text, target_lnum)
    table.insert(lines, text)
    if target_lnum then
      line_targets[#lines] = target_lnum
    end
  end

  add_line(string.format(" 󰍔 Spec Health & LLM Readiness: %s", meta.title or "Untitled Spec"))
  add_line(" " .. string.rep("─", 68))

  local status_str = meta.status or "UNSPECIFIED"
  local ver_str = meta.version and ("v" .. meta.version) or "unversioned"
  add_line(string.format("   Status: %-14s  Version: %-12s  Readiness: %d/100", "[" .. status_str .. "]", ver_str, analysis.readiness), meta.status_lnum or 1)
  add_line(string.format("   Progress: %s", make_progress_bar(t.checked, t.total_tasks, 22)))
  add_line(string.format(
    "   Summary:  󰄵 %d Done  │  󰄱 %d Todo  │  󰄰 %d WIP  │  󰀦 %d Blockers  │  󰋽 %d Questions",
    t.checked, t.unchecked, t.progress, t.important, t.question
  ))
  add_line(string.format(
    "   Assets:   󰡷 %d Diagrams  │  󰓫 %d Tables  │  󰅒 %d Reqs  │  󰅩 %d Code Refs",
    t.diagrams, t.tables, #analysis.reqs, #analysis.refs
  ))
  add_line("")

  -- Section Breakdown
  add_line(" 󰲡 Section Breakdown & Rollups (Press <CR> to jump)")
  add_line(" " .. string.rep("─", 68))
  for _, sec in ipairs(analysis.sections) do
    local indent = string.rep("  ", math.max(0, sec.level - 1))
    local c = sec.counts
    local badge_parts = {}
    if c.total_tasks > 0 then
      table.insert(badge_parts, string.format("%d/%d ✓", c.checked, c.total_tasks))
    end
    if c.important > 0 then
      table.insert(badge_parts, string.format("!%d", c.important))
    end
    if c.question > 0 then
      table.insert(badge_parts, string.format("?%d", c.question))
    end
    if c.diagrams > 0 then
      table.insert(badge_parts, string.format("󰡷 %d", c.diagrams))
    end
    local badge_str = #badge_parts > 0 and ("  [" .. table.concat(badge_parts, " · ") .. "]") or ""
    add_line(string.format("   %s• %s%s  (L%d)", indent, sec.title, badge_str, sec.lnum), sec.lnum)
  end
  add_line("")

  -- Open Questions & Blockers
  if t.important > 0 or t.question > 0 then
    add_line(" 󰀦 Open Questions & Blockers")
    add_line(" " .. string.rep("─", 68))
    for _, item in ipairs(analysis.items) do
      if item.kind == "blocker" or item.kind == "question" then
        add_line(string.format("   %s [%s] %s  (L%d)", item.icon, item.kind:upper(), item.text, item.lnum), item.lnum)
      end
    end
    add_line("")
  end

  -- Code & Test Traceability
  add_line(" 󰌹 Code & Test Traceability Links")
  add_line(" " .. string.rep("─", 68))
  if #analysis.refs == 0 then
    add_line("   (No @impl, @test, or local file links found. Add `@impl: path/to/file` in sections)")
  else
    for _, ref in ipairs(analysis.refs) do
      local status_icon = ref.exists and "󰄵 Ready" or "󰀦 Missing"
      add_line(
        string.format("   %-6s  %-36s  [%s]  (L%d)", "@" .. ref.role, ref.raw, status_icon, ref.lnum),
        ref.lnum
      )
    end
  end
  add_line("")

  -- Spec Lint Diagnostics
  add_line(string.format(" 󰅒 Spec Lint & LLM Clarity Checks (%d findings)", #lint_issues))
  add_line(" " .. string.rep("─", 68))
  if #lint_issues == 0 then
    add_line("   󰄵 All sections pass clarity checks!")
  else
    for _, iss in ipairs(lint_issues) do
      add_line(string.format("   • [L%d] %s", iss.lnum, iss.message), iss.lnum)
    end
  end

  add_line("")
  add_line(" [q/<Esc>] Close   [<CR>] Jump to Line   [s] Cycle Status   [c] Copy LLM Context   [g] Gen Code   [t] Gen Tests")

  dash_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(dash_buf, 0, -1, false, lines)
  vim.bo[dash_buf].modifiable = false
  vim.bo[dash_buf].buftype = "nofile"
  vim.bo[dash_buf].bufhidden = "wipe"
  vim.bo[dash_buf].filetype = "supermarkdown_dashboard"

  local width = math.min(84, math.floor(vim.o.columns * 0.88))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.85))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  dash_win = vim.api.nvim_open_win(dash_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
    style = "minimal",
    border = "rounded",
    title = " 󰍔 SuperMarkdown Spec Dashboard ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = dash_win })
  pcall(vim.api.nvim_set_option_value, "wrap", false, { win = dash_win })

  -- Highlight headers in dashboard
  for idx, l in ipairs(lines) do
    if idx == 1 then
      pcall(vim.api.nvim_buf_set_extmark, dash_buf, NS_DASH, idx - 1, 0, { line_hl_group = "SuperMarkdownH1Bg" })
    elseif l:match("^ 󰲡") or l:match("^ 󰀦") or l:match("^ 󰌹") or l:match("^ 󰅒") then
      pcall(vim.api.nvim_buf_set_extmark, dash_buf, NS_DASH, idx - 1, 0, { line_hl_group = "SuperMarkdownH2" })
    elseif l:match("^ ───") then
      pcall(vim.api.nvim_buf_set_extmark, dash_buf, NS_DASH, idx - 1, 0, { line_hl_group = "SuperMarkdownDivider" })
    end
  end

  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = dash_buf, nowait = true, silent = true })
  end

  map("q", M.close_dashboard)
  map("<Esc>", M.close_dashboard)
  map("<CR>", function()
    local cur = vim.api.nvim_win_get_cursor(dash_win)[1]
    local target_lnum = line_targets[cur]
    if target_lnum and vim.api.nvim_win_is_valid(source_win) then
      M.close_dashboard()
      vim.api.nvim_set_current_win(source_win)
      vim.api.nvim_win_set_cursor(source_win, { target_lnum, 0 })
      vim.cmd("normal! zvzz")
    end
  end)
  map("s", function()
    M.close_dashboard()
    if vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
      M.cycle_status(source_buf)
      M.dashboard(source_buf)
    end
  end)
  map("c", function()
    M.close_dashboard()
    require("super-markdown.llm").copy_context(source_buf)
  end)
  map("g", function()
    M.close_dashboard()
    require("super-markdown.llm").generate_code(source_buf)
  end)
  map("t", function()
    M.close_dashboard()
    require("super-markdown.llm").generate_tests(source_buf)
  end)

  return {
    win = dash_win,
    buf = dash_buf,
    analysis = analysis,
    lint_issues = lint_issues,
  }
end

return M
