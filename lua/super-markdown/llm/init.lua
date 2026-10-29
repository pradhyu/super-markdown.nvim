local config = require("super-markdown.config")
local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local prompt_win = nil
local prompt_buf = nil

--- Estimate token count (~4 chars per token heuristic)
--- @param text string
--- @return number
function M.estimate_tokens(text)
  if not text or text == "" then return 0 end
  return math.max(1, math.ceil(#text / 4))
end

--- Copy text to both system (+) and unnamed ("") registers safely
--- @param text string
function M.copy_to_clipboard(text)
  pcall(vim.fn.setreg, '"', text)
  pcall(vim.fn.setreg, "+", text)
end

--- Read a local file (or line range) for inclusion in an LLM context bundle
--- @param ref table Reference object from analyzer
--- @param max_lines number|nil
--- @return string|nil content
local function read_ref_snippet(ref, max_lines)
  max_lines = max_lines or 200
  if not ref or not ref.exists or not ref.path then return nil end
  local ok, file_lines = pcall(vim.fn.readfile, ref.path)
  if not ok or not file_lines then return nil end

  local s_line = ref.start_line or 1
  local e_line = ref.end_line or math.min(#file_lines, s_line + max_lines - 1)
  s_line = math.max(1, math.min(#file_lines, s_line))
  e_line = math.max(s_line, math.min(#file_lines, e_line))

  local slice = {}
  for i = s_line, e_line do
    table.insert(slice, file_lines[i])
  end
  return table.concat(slice, "\n")
end

--- Assemble a structured LLM context bundle for the section under cursor (or full document)
--- @param bufnr number|nil
--- @param lnum number|nil
--- @param opts table|nil { full_doc = boolean, include_linked_files = boolean }
--- @return table bundle
function M.bundle_section(bufnr, lnum, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  opts = opts or {}

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sec, analysis = analyzer.get_section_at(bufnr, lnum)
  local meta = analysis.metadata

  local start_line = 1
  local end_line = #lines
  local section_title = meta.title or "Full Document"

  if sec and not opts.full_doc then
    start_line = sec.lnum
    end_line = sec.subtree_end_lnum or sec.end_lnum or #lines
    section_title = sec.title
  end

  -- Build breadcrumb path from parent headings
  local breadcrumbs = {}
  if sec and not opts.full_doc then
    local target_level = sec.level
    for i = #analysis.sections, 1, -1 do
      local candidate = analysis.sections[i]
      if candidate.lnum <= sec.lnum and candidate.level < target_level then
        table.insert(breadcrumbs, 1, candidate.title)
        target_level = candidate.level
      end
    end
    table.insert(breadcrumbs, sec.title)
  else
    table.insert(breadcrumbs, section_title)
  end

  local section_lines = {}
  for i = start_line, math.min(#lines, end_line) do
    table.insert(section_lines, lines[i])
  end
  local section_markdown = table.concat(section_lines, "\n")

  -- Gather linked files in this section subtree
  local linked_files = {}
  local seen_paths = {}
  local target_refs = (sec and not opts.full_doc and sec.rollup_refs) or analysis.refs or {}

  if opts.include_linked_files ~= false then
    for _, ref in ipairs(target_refs) do
      local key = (ref.path or ref.raw) .. ":" .. tostring(ref.start_line or "")
      if not seen_paths[key] then
        seen_paths[key] = true
        local snippet = read_ref_snippet(ref, 250)
        table.insert(linked_files, {
          role = ref.role,
          raw = ref.raw,
          path = ref.path,
          exists = ref.exists,
          start_line = ref.start_line,
          end_line = ref.end_line,
          content = snippet,
        })
      end
    end
  end

  -- Format structured bundle text
  local out = {}
  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
  if file_name == "" then file_name = "SPEC.md" end

  table.insert(out, "<spec_context>")
  table.insert(out, string.format("Document: %s (%s)", meta.title or file_name, file_name))
  if meta.status then
    table.insert(out, string.format("Status: %s%s", meta.status, meta.version and (" (v" .. meta.version .. ")") or ""))
  end
  table.insert(out, string.format("Section Path: %s (Lines %d-%d)", table.concat(breadcrumbs, " > "), start_line, end_line))
  table.insert(out, "")
  table.insert(out, "## Specification Content")
  table.insert(out, section_markdown)

  if #linked_files > 0 then
    table.insert(out, "")
    table.insert(out, "## Referenced Implementation & Test Files")
    for _, lf in ipairs(linked_files) do
      local range_label = lf.start_line and string.format(" (L%d-%d)", lf.start_line, lf.end_line or lf.start_line) or ""
      if lf.exists and lf.content then
        local ext = vim.fn.fnamemodify(lf.path, ":e")
        table.insert(out, string.format("### `@%s`: `%s`%s", lf.role, lf.raw, range_label))
        table.insert(out, "```" .. (ext ~= "" and ext or "text"))
        table.insert(out, lf.content)
        table.insert(out, "```")
      else
        table.insert(out, string.format("- Target `@%s`: `%s` (to be created)", lf.role, lf.raw))
      end
    end
  end
  table.insert(out, "</spec_context>")

  local bundle_text = table.concat(out, "\n")
  local tokens = M.estimate_tokens(bundle_text)

  return {
    bufnr = bufnr,
    section = sec,
    section_title = section_title,
    breadcrumbs = breadcrumbs,
    start_line = start_line,
    end_line = end_line,
    markdown = section_markdown,
    linked_files = linked_files,
    text = bundle_text,
    tokens = tokens,
    line_count = #section_lines,
  }
end

--- Build an LLM prompt to generate implementation code from the active spec section
--- @param bufnr number|nil
--- @param lnum number|nil
--- @return table prompt_result
function M.build_code_prompt(bufnr, lnum)
  local bundle = M.bundle_section(bufnr, lnum)
  local impl_targets = {}
  for _, lf in ipairs(bundle.linked_files) do
    if lf.role == "impl" or lf.role == "link" then
      table.insert(impl_targets, lf.raw)
    end
  end

  local target_instruction = #impl_targets > 0
    and ("Target implementation file(s): `" .. table.concat(impl_targets, "`, `") .. "`")
    or "Propose modular file path(s) and clean public API interfaces."

  local lines = {
    "# Task: Implement Specification Section",
    "",
    "You are an expert software engineer implementing the specification below.",
    target_instruction,
    "",
    "## Implementation Guidelines",
    "1. Satisfy every requirement (`REQ-*`), acceptance checkbox (`- [ ]`), and table constraint in the spec.",
    "2. Follow the exact control/data flow depicted in any Mermaid diagrams.",
    "3. Handle edge cases, timeouts, and error conditions explicitly.",
    "4. Keep the implementation clean, idiomatic, and maintainable.",
    "",
    bundle.text,
  }

  local text = table.concat(lines, "\n")
  return {
    kind = "code",
    title = "LLM Code Generation Prompt: " .. bundle.section_title,
    text = text,
    tokens = M.estimate_tokens(text),
    bundle = bundle,
  }
end

--- Build an LLM prompt to generate application & unit tests from the active spec section
--- @param bufnr number|nil
--- @param lnum number|nil
--- @return table prompt_result
function M.build_test_prompt(bufnr, lnum)
  local bundle = M.bundle_section(bufnr, lnum)
  local test_targets = {}
  for _, lf in ipairs(bundle.linked_files) do
    if lf.role == "test" then
      table.insert(test_targets, lf.raw)
    end
  end

  local target_instruction = #test_targets > 0
    and ("Target test suite file(s): `" .. table.concat(test_targets, "`, `") .. "`")
    or "Create a self-contained, executable automated test suite."

  local lines = {
    "# Task: Generate Application & Unit Tests from Specification",
    "",
    "You are a Staff Test & Reliability Engineer writing comprehensive automated tests directly from the specification below.",
    target_instruction,
    "",
    "## Test Coverage Requirements",
    "1. **Happy Path & Functional Requirements**: Write at least one test assertion per requirement (`REQ-*`) and task item (`- [ ]` / `- [x]`).",
    "2. **State & Sequence Transitions**: Verify every branch, `alt`/`else` block, and state transition in the Mermaid diagrams.",
    "3. **Data Table & Boundary Matrix**: Convert every row in specification tables into parameterized test cases (including SLO/timeout boundaries).",
    "4. **Negative & Error Cases**: Assert proper failure behavior for invalid inputs, unauthorized access, and edge conditions.",
    "",
    bundle.text,
  }

  local text = table.concat(lines, "\n")
  return {
    kind = "tests",
    title = "LLM Test Suite Generation Prompt: " .. bundle.section_title,
    text = text,
    tokens = M.estimate_tokens(text),
    bundle = bundle,
  }
end

--- Build an LLM prompt to critique, refine, and expand the active spec section
--- @param bufnr number|nil
--- @param lnum number|nil
--- @return table prompt_result
function M.build_review_prompt(bufnr, lnum)
  local bundle = M.bundle_section(bufnr, lnum)
  local lint_issues = analyzer.lint(bundle.bufnr, false)
  local section_lints = {}
  for _, iss in ipairs(lint_issues) do
    if iss.lnum >= bundle.start_line and iss.lnum <= bundle.end_line then
      table.insert(section_lints, string.format("- Line %d: %s", iss.lnum, iss.message))
    end
  end

  local lines = {
    "# Task: Review, Tighten & Expand Technical Specification",
    "",
    "Review the specification section below so it is unambiguous and ready for deterministic code and test generation.",
    "",
    "## Expected Output",
    "1. Resolve any open questions (`[?]`), blockers (`[!]`), or ambiguous phrasing.",
    "2. Add or refine a **Mermaid diagram** (`graph TD` or `sequenceDiagram`) if control flow is implicit.",
    "3. Add a concrete **Edge Case / Requirement Table** (`| Req ID | Scenario | Expected Behavior | Verification |`).",
    "4. Output clean GitHub-Flavored Markdown ready to paste back into the spec.",
  }

  if #section_lints > 0 then
    table.insert(lines, "")
    table.insert(lines, "## Detected Spec Lint Warnings to Resolve")
    vim.list_extend(lines, section_lints)
  end

  table.insert(lines, "")
  table.insert(lines, bundle.text)

  local text = table.concat(lines, "\n")
  return {
    kind = "review",
    title = "LLM Spec Co-Author & Review Prompt: " .. bundle.section_title,
    text = text,
    tokens = M.estimate_tokens(text),
    bundle = bundle,
  }
end

--- Close the floating LLM Prompt Studio window if open
function M.close_prompt_window()
  if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
    pcall(vim.api.nvim_win_close, prompt_win, true)
  end
  prompt_win = nil
  prompt_buf = nil
end

--- Dispatch a prompt string to a CLI LLM tool asynchronously and show output in a split/float
--- @param prompt_text string
--- @param source_buf number|nil
--- @param insert_after_line number|nil
function M.dispatch_to_cli(prompt_text, source_buf, insert_after_line)
  local llm_opts = (config.options and config.options.llm) or {}
  local cmd = llm_opts.cmd

  -- Auto-detect available CLI agent if cmd is "auto" or nil
  if not cmd or cmd == "" or cmd == "auto" then
    local candidates = {
      { bin = "claude", args = { "claude", "-p" } },
      { bin = "gemini", args = { "gemini", "-p" } },
      { bin = "llm", args = { "llm" } },
      { bin = "agy", args = { "agy", "chat" } },
    }
    for _, c in ipairs(candidates) do
      if vim.fn.executable(c.bin) == 1 then
        cmd = c.args
        break
      end
    end
  elseif type(cmd) == "string" then
    cmd = vim.split(cmd, "%s+")
  end

  if not cmd then
    M.copy_to_clipboard(prompt_text)
    vim.notify(
      "SuperMarkdown: Prompt copied to clipboard! (Configure `llm.cmd` in setup to stream directly from a CLI tool)",
      vim.log.levels.INFO
    )
    return
  end

  vim.notify("SuperMarkdown: Dispatching spec prompt to `" .. table.concat(cmd, " ") .. "` 󰚩 ...", vim.log.levels.INFO)

  vim.system(cmd, { stdin = prompt_text, text = true }, function(res)
    vim.schedule(function()
      local out_text = (res.stdout and res.stdout ~= "" and res.stdout) or (res.stderr or "")
      if res.code ~= 0 and out_text == "" then
        vim.notify("SuperMarkdown LLM CLI exited with code " .. tostring(res.code), vim.log.levels.ERROR)
        return
      end

      local out_lines = vim.split(out_text, "\n", { plain = true })
      if insert_after_line and source_buf and vim.api.nvim_buf_is_valid(source_buf) then
        local wrapped = { "", "<!-- LLM Generated Output -->" }
        vim.list_extend(wrapped, out_lines)
        vim.api.nvim_buf_set_lines(source_buf, insert_after_line, insert_after_line, false, wrapped)
        vim.notify("SuperMarkdown: Inserted LLM response into spec buffer 󰄵", vim.log.levels.INFO)
      else
        -- Open response buffer in vertical split
        vim.cmd("botright vsplit")
        local rwin = vim.api.nvim_get_current_win()
        local rbuf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(rwin, rbuf)
        vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, out_lines)
        vim.bo[rbuf].filetype = "markdown"
        vim.bo[rbuf].buftype = "nofile"
        vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = rbuf, silent = true })
        vim.notify("SuperMarkdown: LLM response ready 󰄵 (press 'q' to close split)", vim.log.levels.INFO)
      end
    end)
  end)
end

--- Open the interactive Floating LLM Prompt Studio window
--- @param prompt_obj table { title, text, tokens, bundle }
--- @param opts table|nil
function M.open_prompt_window(prompt_obj, opts)
  opts = opts or {}
  M.copy_to_clipboard(prompt_obj.text)

  if opts.silent or (config.options.llm and config.options.llm.open_studio == false) then
    vim.notify(
      string.format("SuperMarkdown: Copied '%s' (~%d tokens, %d linked files) 󰅍", prompt_obj.title, prompt_obj.tokens, #prompt_obj.bundle.linked_files),
      vim.log.levels.INFO
    )
    return prompt_obj
  end

  M.close_prompt_window()

  prompt_buf = vim.api.nvim_create_buf(false, true)
  local prompt_lines = vim.split(prompt_obj.text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, prompt_lines)
  vim.bo[prompt_buf].filetype = "markdown"
  vim.bo[prompt_buf].buftype = "nofile"
  vim.bo[prompt_buf].bufhidden = "wipe"

  local width = math.min(96, math.floor(vim.o.columns * 0.85))
  local height = math.min(math.max(16, #prompt_lines + 2), math.floor(vim.o.lines * 0.80))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local title = string.format(" 󰚩 %s (~%d tokens) ", prompt_obj.title, prompt_obj.tokens)
  local footer = " [y/<CR>] Yank & Close   [r] Run LLM CLI   [i] Run & Insert into Spec   [q/<Esc>] Close "

  local win_cfg = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }
  if vim.fn.has("nvim-0.10") == 1 then
    win_cfg.footer = footer
    win_cfg.footer_pos = "center"
  end

  prompt_win = vim.api.nvim_open_win(prompt_buf, true, win_cfg)
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = prompt_win })
  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = prompt_win })

  local function get_current_text()
    local cur_lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
    return table.concat(cur_lines, "\n")
  end

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = prompt_buf, nowait = true, silent = true })
  end

  bmap("q", M.close_prompt_window)
  bmap("<Esc>", M.close_prompt_window)
  bmap("y", function()
    local txt = get_current_text()
    M.copy_to_clipboard(txt)
    M.close_prompt_window()
    vim.notify(string.format("SuperMarkdown: Copied LLM prompt (~%d tokens) to clipboard 󰅍", M.estimate_tokens(txt)), vim.log.levels.INFO)
  end)
  bmap("<CR>", function()
    local txt = get_current_text()
    M.copy_to_clipboard(txt)
    M.close_prompt_window()
    vim.notify(string.format("SuperMarkdown: Copied LLM prompt (~%d tokens) to clipboard 󰅍", M.estimate_tokens(txt)), vim.log.levels.INFO)
  end)
  bmap("r", function()
    local txt = get_current_text()
    M.close_prompt_window()
    M.dispatch_to_cli(txt, prompt_obj.bundle.bufnr, nil)
  end)
  bmap("i", function()
    local txt = get_current_text()
    M.close_prompt_window()
    M.dispatch_to_cli(txt, prompt_obj.bundle.bufnr, prompt_obj.bundle.end_line)
  end)

  vim.notify(
    string.format("SuperMarkdown: Prompt copied to clipboard (~%d tokens) — edit or press [r] to run LLM CLI", prompt_obj.tokens),
    vim.log.levels.INFO
  )
  return prompt_obj
end

--- Copy the current section's Spec Context Bundle to clipboard
--- @param bufnr number|nil
--- @param full_doc boolean|nil
function M.copy_context(bufnr, full_doc)
  local bundle = M.bundle_section(bufnr, nil, { full_doc = full_doc })
  M.copy_to_clipboard(bundle.text)
  vim.notify(
    string.format(
      "SuperMarkdown: Copied spec context '%s' (%d lines, %d linked files, ~%d tokens) 󰅍",
      bundle.section_title,
      bundle.line_count,
      #bundle.linked_files,
      bundle.tokens
    ),
    vim.log.levels.INFO
  )
  return bundle
end

--- Generate LLM Implementation Code Prompt for the current section
--- @param bufnr number|nil
--- @param opts table|nil
function M.generate_code(bufnr, opts)
  local prompt_obj = M.build_code_prompt(bufnr)
  return M.open_prompt_window(prompt_obj, opts)
end

--- Generate LLM Application Tests Prompt for the current section
--- @param bufnr number|nil
--- @param opts table|nil
function M.generate_tests(bufnr, opts)
  local prompt_obj = M.build_test_prompt(bufnr)
  return M.open_prompt_window(prompt_obj, opts)
end

--- Generate LLM Spec Review & Co-Author Prompt for the current section
--- @param bufnr number|nil
--- @param opts table|nil
function M.review_spec(bufnr, opts)
  local prompt_obj = M.build_review_prompt(bufnr)
  return M.open_prompt_window(prompt_obj, opts)
end

return M
