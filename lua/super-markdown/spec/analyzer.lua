local M = {}

local NS_LINT = vim.api.nvim_create_namespace("super_markdown_spec_lint")

-- Ambiguous / vague specification phrases that hurt LLM code/test generation accuracy
M.AMBIGUOUS_PATTERNS = {
  { pattern = "%f[%a][sS]hould be fast%f[%A]", msg = "Vague performance requirement ('should be fast') — specify target latency/throughput SLO (e.g., '< 50ms p99')." },
  { pattern = "%f[%a][aA]s fast as possible%f[%A]", msg = "Unbounded performance phrase ('as fast as possible') — define concrete numeric bounds." },
  { pattern = "%f[%a][hH]andle errors gracefully%f[%A]", msg = "Ambiguous error handling ('handle errors gracefully') — specify exact error codes, retry policy, or fallback behavior." },
  { pattern = "%f[%a][eE]tc%.?", msg = "Open-ended list ('etc.') — enumerate all expected cases explicitly for deterministic LLM code generation." },
  { pattern = "%f[%a][tT][bB][dD]%f[%A]", msg = "Unresolved placeholder ('TBD') — resolve before generating implementation." },
  { pattern = "%f[%a][tT][oO][dD][oO]%f[%A]", msg = "Unresolved 'TODO' marker in specification text." },
  { pattern = "%f[%a][mM]aybe%f[%A]", msg = "Uncertain specification language ('maybe') — decide on definitive requirement." },
  { pattern = "%f[%a][sS]eamlessly%f[%A]", msg = "Non-testable adverb ('seamlessly') — state the concrete integration contract." },
}

--- Resolve a relative or file:// path to a normalized filesystem path
--- @param raw_path string
--- @param bufnr number
--- @return string|nil path, number|nil start_line, number|nil end_line
function M.resolve_reference(raw_path, bufnr)
  if not raw_path or raw_path == "" then return nil end
  local clean = vim.trim(raw_path)

  -- Ignore external URLs or pure markdown anchors
  if clean:match("^https?://") or clean:match("^mailto:") or clean:match("^#") then
    return nil
  end

  -- Strip file:// prefix
  clean = clean:gsub("^file://", "")

  -- Extract #L10-L20 or :10:20 or :10 line ranges
  local file_part = clean
  local start_line, end_line = nil, nil

  local p1, s1, e1 = clean:match("^(.+)#[lL](%d+)%-?[lL]?(%d*)$")
  if p1 then
    file_part = p1
    start_line = tonumber(s1)
    end_line = tonumber(e1) or start_line
  else
    local p2, s2, e2 = clean:match("^(.+):(%d+):?(%d*)$")
    if p2 then
      file_part = p2
      start_line = tonumber(s2)
      end_line = tonumber(e2) or start_line
    end
  end

  local current_file = vim.api.nvim_buf_get_name(bufnr or 0)
  local current_dir = (current_file ~= "" and vim.fs.dirname(current_file)) or vim.fn.getcwd()

  local candidates = {
    file_part,
    vim.fs.normalize(current_dir .. "/" .. file_part),
    vim.fs.normalize(vim.fn.getcwd() .. "/" .. file_part),
  }

  for _, cand in ipairs(candidates) do
    if vim.fn.filereadable(cand) == 1 then
      return cand, start_line, end_line
    end
  end

  return file_part, start_line, end_line
end

--- Parse document metadata (YAML frontmatter or top blockquote metadata like `> **Document Status**: APPROVED`)
--- @param lines string[]
--- @return table metadata
function M.parse_metadata(lines)
  local meta = {
    title = nil,
    status = nil,
    version = nil,
    owner = nil,
    target_release = nil,
    fields = {},
    status_lnum = nil,
  }

  local in_frontmatter = false
  for i, line in ipairs(lines) do
    if i == 1 and line:match("^---%s*$") then
      in_frontmatter = true
    elseif in_frontmatter then
      if line:match("^---%s*$") or line:match("^%.%.%.%s*$") then
        in_frontmatter = false
      else
        local k, v = line:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
        if k and v then
          local clean_v = v:gsub("^['\"`]", ""):gsub("['\"`]$", "")
          local kl = k:lower()
          meta.fields[kl] = clean_v
          if kl == "status" then
            meta.status = clean_v:upper()
            meta.status_lnum = i
          elseif kl == "version" then
            meta.version = clean_v
          elseif kl == "owner" or kl == "author" then
            meta.owner = clean_v
          elseif kl == "title" and not meta.title then
            meta.title = clean_v
          end
        end
      end
    else
      if not meta.title then
        local h1 = line:match("^#%s+(.+)$")
        if h1 then
          meta.title = vim.trim(h1)
        end
      end

      -- Also support blockquote metadata headers: e.g. `> **Document Status**: `APPROVED``
      if i <= 25 then
        local bq_key, bq_val = line:match("^>%s*%*%*([^%*]+)%*%*%s*:%s*(.-)%s*$")
        if bq_key and bq_val then
          local clean_v = bq_val:gsub("^`", ""):gsub("`$", "")
          local kl = bq_key:lower()
          meta.fields[kl] = clean_v
          if kl:find("status") then
            meta.status = clean_v:upper()
            meta.status_lnum = i
          elseif kl:find("version") then
            meta.version = clean_v
          elseif kl:find("owner") or kl:find("author") or kl:find("master") then
            meta.owner = clean_v
          elseif kl:find("release") or kl:find("duration") then
            meta.target_release = clean_v
          end
        end
      end
    end
  end

  return meta
end

--- Analyze a markdown buffer and extract sections, tasks, questions, requirements, and code traceability
--- @param bufnr number
--- @return table analysis
function M.analyze(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local metadata = M.parse_metadata(lines)

  local sections = {}
  local all_items = {} -- semantic items for picker
  local refs = {}      -- all file/code references
  local reqs = {}      -- requirement IDs (REQ-01, FR-02, etc.)

  local totals = {
    checked = 0,
    unchecked = 0,
    progress = 0,
    canceled = 0,
    important = 0,
    question = 0,
    total_tasks = 0,
    diagrams = 0,
    tables = 0,
    codeblocks = 0,
    impl_refs = 0,
    test_refs = 0,
  }

  local current_section = nil
  local in_codeblock = false
  local code_lang = nil
  local code_start = nil
  local in_table = false

  local function ensure_root_section()
    if not current_section then
      current_section = {
        lnum = 1,
        end_lnum = #lines,
        level = 1,
        title = metadata.title or "Document Root",
        counts = {
          checked = 0,
          unchecked = 0,
          progress = 0,
          canceled = 0,
          important = 0,
          question = 0,
          total_tasks = 0,
          diagrams = 0,
          tables = 0,
          codeblocks = 0,
        },
        refs = {},
        reqs = {},
      }
      table.insert(sections, current_section)
    end
    return current_section
  end

  for lnum, line in ipairs(lines) do
    local fence_lang = line:match("^%s*```+([%w_%-%+]*)") or line:match("^%s*~~~+([%w_%-%+]*)")
    if fence_lang then
      if not in_codeblock then
        in_codeblock = true
        code_lang = vim.trim(fence_lang):lower()
        code_start = lnum
        local sec = ensure_root_section()
        if code_lang == "mermaid" then
          sec.counts.diagrams = sec.counts.diagrams + 1
          totals.diagrams = totals.diagrams + 1
          table.insert(all_items, {
            kind = "diagram",
            icon = "󰡷 ",
            lnum = lnum,
            text = string.format("Mermaid Diagram (%s)", sec.title),
            section = sec.title,
            bufnr = bufnr,
          })
        else
          sec.counts.codeblocks = sec.counts.codeblocks + 1
          totals.codeblocks = totals.codeblocks + 1
        end
      else
        in_codeblock = false
        code_lang = nil
        code_start = nil
      end
    elseif not in_codeblock then
      -- 1. Headings
      local hashes, h_title = line:match("^(#+)%s+(.*)$")
      if hashes and #hashes <= 6 and h_title then
        if current_section then
          current_section.end_lnum = lnum - 1
        end
        current_section = {
          lnum = lnum,
          end_lnum = #lines,
          level = #hashes,
          title = vim.trim(h_title),
          counts = {
            checked = 0,
            unchecked = 0,
            progress = 0,
            canceled = 0,
            important = 0,
            question = 0,
            total_tasks = 0,
            diagrams = 0,
            tables = 0,
            codeblocks = 0,
          },
          refs = {},
          reqs = {},
        }
        table.insert(sections, current_section)
        in_table = false
      else
        local sec = ensure_root_section()

        -- 2. Tables
        if line:match("^%s*|.*|%s*$") then
          if not in_table then
            in_table = true
            sec.counts.tables = sec.counts.tables + 1
            totals.tables = totals.tables + 1
            table.insert(all_items, {
              kind = "table",
              icon = "󰓫 ",
              lnum = lnum,
              text = string.format("Table in %s: %s", sec.title, vim.trim(line)),
              section = sec.title,
              bufnr = bufnr,
            })
          end
        else
          in_table = false
        end

        -- 3. Checkboxes
        local cb_state, cb_text = line:match("^%s*[%-%*%+]%s+%[(.)%]%s*(.*)$")
        if not cb_state then
          cb_state, cb_text = line:match("^%s*%d+%.%s+%[(.)%]%s*(.*)$")
        end
        if cb_state then
          cb_text = vim.trim(cb_text or "")
          if cb_state == "x" or cb_state == "X" then
            sec.counts.checked = sec.counts.checked + 1
            sec.counts.total_tasks = sec.counts.total_tasks + 1
            totals.checked = totals.checked + 1
            totals.total_tasks = totals.total_tasks + 1
          elseif cb_state == " " then
            sec.counts.unchecked = sec.counts.unchecked + 1
            sec.counts.total_tasks = sec.counts.total_tasks + 1
            totals.unchecked = totals.unchecked + 1
            totals.total_tasks = totals.total_tasks + 1
            table.insert(all_items, {
              kind = "task",
              icon = "󰄱 ",
              lnum = lnum,
              text = cb_text,
              section = sec.title,
              bufnr = bufnr,
            })
          elseif cb_state == "/" then
            sec.counts.progress = sec.counts.progress + 1
            sec.counts.total_tasks = sec.counts.total_tasks + 1
            totals.progress = totals.progress + 1
            totals.total_tasks = totals.total_tasks + 1
            table.insert(all_items, {
              kind = "task",
              icon = "󰄰 ",
              lnum = lnum,
              text = "[WIP] " .. cb_text,
              section = sec.title,
              bufnr = bufnr,
            })
          elseif cb_state == "-" then
            sec.counts.canceled = sec.counts.canceled + 1
            totals.canceled = totals.canceled + 1
          elseif cb_state == "!" then
            sec.counts.important = sec.counts.important + 1
            sec.counts.total_tasks = sec.counts.total_tasks + 1
            totals.important = totals.important + 1
            totals.total_tasks = totals.total_tasks + 1
            table.insert(all_items, {
              kind = "blocker",
              icon = "󰀦 ",
              lnum = lnum,
              text = cb_text,
              section = sec.title,
              bufnr = bufnr,
            })
          elseif cb_state == "?" then
            sec.counts.question = sec.counts.question + 1
            totals.question = totals.question + 1
            table.insert(all_items, {
              kind = "question",
              icon = "󰋽 ",
              lnum = lnum,
              text = cb_text,
              section = sec.title,
              bufnr = bufnr,
            })
          end
        end

        -- 4. Callouts (> [!TYPE] Title)
        local callout_type, callout_rest = line:match("^%s*>%s*%[!([%a_]+)%]%s*(.*)$")
        if callout_type then
          local ctype = callout_type:upper()
          if ctype == "QUESTION" then
            sec.counts.question = sec.counts.question + 1
            totals.question = totals.question + 1
            table.insert(all_items, {
              kind = "question",
              icon = "󰋽 ",
              lnum = lnum,
              text = callout_rest ~= "" and callout_rest or "Open Question Callout",
              section = sec.title,
              bufnr = bufnr,
            })
          elseif ctype == "WARNING" or ctype == "CAUTION" or ctype == "DANGER" or ctype == "IMPORTANT" then
            table.insert(all_items, {
              kind = "callout",
              icon = "󰀦 ",
              lnum = lnum,
              text = string.format("[%s] %s", ctype, callout_rest ~= "" and callout_rest or sec.title),
              section = sec.title,
              bufnr = bufnr,
            })
          end
        end

        -- 5. Requirement IDs (e.g. REQ-01, FR-101, NFR-02, SEC-01)
        for req_id in line:gmatch("%f[%w]([A-Z][A-Z0-9]?[A-Z0-9]?%-%d+)%f[%W]") do
          local prefix = req_id:match("^([A-Z]+)%-")
          if prefix == "REQ" or prefix == "FR" or prefix == "NFR" or prefix == "SEC" or prefix == "API" or prefix == "UC" then
            local entry = {
              id = req_id,
              lnum = lnum,
              line = vim.trim(line),
              section = sec.title,
            }
            table.insert(sec.reqs, entry)
            table.insert(reqs, entry)
            table.insert(all_items, {
              kind = "requirement",
              icon = "󰅒 ",
              lnum = lnum,
              text = string.format("%s: %s", req_id, vim.trim(line)),
              section = sec.title,
              bufnr = bufnr,
            })
          end
        end

        -- 6. Traceability Tags (@impl: path, @test: path)
        for _, role in ipairs({ "impl", "test" }) do
          for tag_target in line:gmatch("@" .. role .. "%s*:%s*([^%s,`%)%]]+)") do
            local resolved, s_line, e_line = M.resolve_reference(tag_target, bufnr)
            local exists = resolved and vim.fn.filereadable(resolved) == 1 or false
            local ref_obj = {
              role = role,
              raw = tag_target,
              path = resolved or tag_target,
              start_line = s_line,
              end_line = e_line,
              exists = exists,
              lnum = lnum,
              section = sec.title,
            }
            table.insert(sec.refs, ref_obj)
            table.insert(refs, ref_obj)
            if role == "impl" then
              totals.impl_refs = totals.impl_refs + 1
            else
              totals.test_refs = totals.test_refs + 1
            end
            table.insert(all_items, {
              kind = "ref",
              icon = role == "test" and "󰙨 " or "󰅩 ",
              lnum = lnum,
              text = string.format("@%s: %s %s", role, tag_target, exists and "(✓)" or "(missing)"),
              section = sec.title,
              bufnr = bufnr,
            })
          end
        end

        -- 7. Markdown file links [label](path)
        for label, target in line:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
          local resolved, s_line, e_line = M.resolve_reference(target, bufnr)
          if resolved then
            local exists = vim.fn.filereadable(resolved) == 1
            local is_test = target:find("test") or target:find("spec")
            local role = is_test and "test" or "link"
            local ref_obj = {
              role = role,
              label = label,
              raw = target,
              path = resolved,
              start_line = s_line,
              end_line = e_line,
              exists = exists,
              lnum = lnum,
              section = sec.title,
            }
            table.insert(sec.refs, ref_obj)
            table.insert(refs, ref_obj)
          end
        end
      end
    end
  end

  -- Compute hierarchical rollup counts so parent headings (e.g., H1/H2) reflect child subheadings
  for i, sec in ipairs(sections) do
    local rollup = vim.deepcopy(sec.counts)
    local rollup_refs = vim.deepcopy(sec.refs)
    local sub_end = sec.end_lnum
    for j = i + 1, #sections do
      if sections[j].level > sec.level then
        for k, v in pairs(sections[j].counts) do
          rollup[k] = (rollup[k] or 0) + v
        end
        for _, r in ipairs(sections[j].refs) do
          table.insert(rollup_refs, r)
        end
        sub_end = sections[j].end_lnum
      else
        break
      end
    end
    sec.subtree_end_lnum = sub_end
    sec.rollup = rollup
    sec.rollup_refs = rollup_refs
  end

  -- Compute Readiness Score (0-100)
  local readiness = 100
  if totals.question > 0 then
    readiness = readiness - math.min(30, totals.question * 10)
  end
  if totals.important > 0 then
    readiness = readiness - math.min(30, totals.important * 10)
  end
  if totals.total_tasks > 0 then
    local completion_ratio = totals.checked / totals.total_tasks
    readiness = math.floor(readiness * (0.5 + 0.5 * completion_ratio))
  end
  readiness = math.max(0, math.min(100, readiness))

  return {
    bufnr = bufnr,
    metadata = metadata,
    sections = sections,
    totals = totals,
    items = all_items,
    refs = refs,
    reqs = reqs,
    readiness = readiness,
  }
end

--- Find the spec section containing the given 1-indexed line number
--- @param bufnr number
--- @param lnum number
--- @return table|nil section, table analysis
function M.get_section_at(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local analysis = M.analyze(bufnr)

  local matched = nil
  for _, sec in ipairs(analysis.sections) do
    if sec.lnum <= lnum then
      matched = sec
    else
      break
    end
  end

  return matched or analysis.sections[1], analysis
end

--- Run spec linter for ambiguous language, open questions, and broken file references
--- @param bufnr number
--- @param publish_diagnostics boolean|nil
--- @return table[] issues
function M.lint(bufnr, publish_diagnostics)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local issues = {}
  local diagnostics = {}

  local in_codeblock = false
  for lnum, line in ipairs(lines) do
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_codeblock = not in_codeblock
    elseif not in_codeblock then
      -- 1. Check ambiguous phrases
      for _, rule in ipairs(M.AMBIGUOUS_PATTERNS) do
        local s, e = line:find(rule.pattern)
        if s then
          local issue = {
            lnum = lnum,
            col = s - 1,
            end_col = e,
            severity = vim.diagnostic.severity.WARN,
            kind = "ambiguity",
            message = rule.msg,
          }
          table.insert(issues, issue)
          table.insert(diagnostics, {
            lnum = lnum - 1,
            col = s - 1,
            end_col = e,
            severity = vim.diagnostic.severity.WARN,
            source = "super-markdown",
            message = rule.msg,
          })
        end
      end

      -- 2. Check unresolved open questions [?]
      local q_s, q_e = line:find("^%s*[%-%*%+]%s+%[%?%]")
      if q_s then
        local msg = "Unresolved Spec Question [?]: Clarify before generating implementation."
        table.insert(issues, {
          lnum = lnum,
          col = q_s - 1,
          end_col = q_e,
          severity = vim.diagnostic.severity.INFO,
          kind = "question",
          message = msg,
        })
        table.insert(diagnostics, {
          lnum = lnum - 1,
          col = q_s - 1,
          end_col = q_e,
          severity = vim.diagnostic.severity.INFO,
          source = "super-markdown",
          message = msg,
        })
      end

      -- 3. Check critical blockers [!]
      local b_s, b_e = line:find("^%s*[%-%*%+]%s+%[!%]")
      if b_s then
        local msg = "Spec Blocker [!]: High-priority blocker flagged in specification."
        table.insert(issues, {
          lnum = lnum,
          col = b_s - 1,
          end_col = b_e,
          severity = vim.diagnostic.severity.ERROR,
          kind = "blocker",
          message = msg,
        })
        table.insert(diagnostics, {
          lnum = lnum - 1,
          col = b_s - 1,
          end_col = b_e,
          severity = vim.diagnostic.severity.ERROR,
          source = "super-markdown",
          message = msg,
        })
      end

      -- 4. Check broken @impl / @test links
      for _, role in ipairs({ "impl", "test" }) do
        local s, e, target = line:find("@" .. role .. "%s*:%s*([^%s,`%)%]]+)")
        if s and target then
          local resolved = M.resolve_reference(target, bufnr)
          if not resolved or vim.fn.filereadable(resolved) == 0 then
            local msg = string.format("Missing @%s file target '%s' — use :SuperMarkdown llm_%s to generate it.", role, target, role == "impl" and "code" or "tests")
            table.insert(issues, {
              lnum = lnum,
              col = s - 1,
              end_col = e,
              severity = vim.diagnostic.severity.HINT,
              kind = "missing_ref",
              message = msg,
            })
            table.insert(diagnostics, {
              lnum = lnum - 1,
              col = s - 1,
              end_col = e,
              severity = vim.diagnostic.severity.HINT,
              source = "super-markdown",
              message = msg,
            })
          end
        end
      end
    end
  end

  if publish_diagnostics then
    vim.diagnostic.set(NS_LINT, bufnr, diagnostics, {})
  end

  return issues
end

function M.clear_lint(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(NS_LINT, bufnr)
end

return M
