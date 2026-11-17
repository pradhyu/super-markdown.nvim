local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local float_win = nil
local float_buf = nil

--- Analyze requirements and compute bidirectional traceability matrix
--- @param bufnr number
--- @return table report
function M.compute(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local reqs = {}
  local cur_req = nil

  for lnum, line in ipairs(lines) do
    -- 1. Explicit REQ / AC IDs (e.g. **REQ-01**: or **AC-01**:)
    local req_id, title = line:match("%*%*([%u%d%-_]+)%*%*%s*:%s*(.*)$")
    if not req_id then
      req_id, title = line:match("^###%s+Scenario%s*:%s*(.*)$")
      if req_id then
        title = req_id
        req_id = "SCENARIO-" .. lnum
      end
    end

    if req_id and title then
      cur_req = {
        id = req_id,
        title = vim.trim(title),
        lnum = lnum,
        impl_refs = {},
        test_refs = {},
        criteria = {},
      }
      table.insert(reqs, cur_req)
    else
      -- Check for @impl: or @test: references
      local impl_target = line:match("@impl%s*:%s*([^%s,`%)%]]+)")
      if impl_target and cur_req then
        local resolved, s_l, e_l = analyzer.resolve_reference(impl_target, bufnr)
        local exists = resolved and vim.fn.filereadable(resolved) == 1
        table.insert(cur_req.impl_refs, {
          target = impl_target,
          resolved = resolved,
          exists = exists,
          line = s_l or 1,
        })
      end

      local test_target = line:match("@test%s*:%s*([^%s,`%)%]]+)")
      if test_target and cur_req then
        local resolved, s_l, e_l = analyzer.resolve_reference(test_target, bufnr)
        local exists = resolved and vim.fn.filereadable(resolved) == 1
        table.insert(cur_req.test_refs, {
          target = test_target,
          resolved = resolved,
          exists = exists,
          line = s_l or 1,
        })
      end
    end
  end

  local total = #reqs
  local implemented = 0
  local tested = 0

  for _, r in ipairs(reqs) do
    if #r.impl_refs > 0 then
      local all_exist = true
      for _, im in ipairs(r.impl_refs) do
        if not im.exists then all_exist = false break end
      end
      if all_exist then implemented = implemented + 1 end
    end
    if #r.test_refs > 0 then
      local all_exist = true
      for _, te in ipairs(r.test_refs) do
        if not te.exists then all_exist = false break end
      end
      if all_exist then tested = tested + 1 end
    end
  end

  local imp_pct = total > 0 and math.floor((implemented / total) * 100) or 0
  local tst_pct = total > 0 and math.floor((tested / total) * 100) or 0

  return {
    total = total,
    implemented = implemented,
    tested = tested,
    impl_pct = imp_pct,
    test_pct = tst_pct,
    requirements = reqs,
    reqs = reqs,
  }
end

--- Open interactive Traceability Matrix floating window
--- @param bufnr? number
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local report = M.compute(bufnr)

  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
    float_win = nil
    float_buf = nil
  end

  float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].filetype = "supermarkdown_traceability"

  local imp_pct = report.total > 0 and math.floor((report.implemented / report.total) * 100) or 0
  local tst_pct = report.total > 0 and math.floor((report.tested / report.total) * 100) or 0

  local lines = {
    " 󰡷 SuperMarkdown Requirement-to-Code Traceability Matrix",
    "─────────────────────────────────────────────────────────────────────────────",
    string.format(" Total Requirements: %d  •  Implemented: %d/%d (%d%%)  •  Tested: %d/%d (%d%%)",
      report.total, report.implemented, report.total, imp_pct, report.tested, report.total, tst_pct),
    "─────────────────────────────────────────────────────────────────────────────",
  }

  local line_to_target = {}

  if report.total == 0 then
    table.insert(lines, "  (No explicit **REQ-***, **AC-***, or Scenario blocks found in spec)")
    table.insert(lines, "  Add identifiers like '**REQ-01**: Description' to enable automatic tracking.")
  else
    for _, r in ipairs(report.requirements) do
      local status_icon = "○"
      if #r.impl_refs > 0 and #r.test_refs > 0 then
        status_icon = "●"
      elseif #r.impl_refs > 0 or #r.test_refs > 0 then
        status_icon = "◐"
      end

      local r_line_idx = #lines + 1
      table.insert(lines, string.format(" [%s] %s: %s (line %d)", status_icon, r.id, r.title, r.lnum))
      line_to_target[r_line_idx] = { bufnr = bufnr, lnum = r.lnum }

      if #r.impl_refs > 0 then
        for _, im in ipairs(r.impl_refs) do
          local im_idx = #lines + 1
          local mark = im.exists and "✓" or "󰀦 MISSING"
          table.insert(lines, string.format("     ├── @impl: %s [%s]", im.target, mark))
          if im.resolved and im.exists then
            line_to_target[im_idx] = { file = im.resolved, lnum = im.line }
          else
            line_to_target[im_idx] = { bufnr = bufnr, lnum = r.lnum }
          end
        end
      else
        table.insert(lines, "     ├── @impl: [UNIMPLEMENTED 󰀦]")
      end

      if #r.test_refs > 0 then
        for _, te in ipairs(r.test_refs) do
          local te_idx = #lines + 1
          local mark = te.exists and "✓" or "󰀦 MISSING"
          table.insert(lines, string.format("     └── @test: %s [%s]", te.target, mark))
          if te.resolved and te.exists then
            line_to_target[te_idx] = { file = te.resolved, lnum = te.line }
          else
            line_to_target[te_idx] = { bufnr = bufnr, lnum = r.lnum }
          end
        end
      else
        table.insert(lines, "     └── @test: [UNTESTED 󰀦]")
      end
      table.insert(lines, "")
    end
  end

  table.insert(lines, "─────────────────────────────────────────────────────────────────────────────")
  table.insert(lines, " [Enter] Jump to Target File/Line    [r] Refresh    [q / <Esc>] Close")

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
    title = " 󰡷 Traceability Matrix ",
    title_pos = "center",
  })

  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = float_win })
  pcall(vim.api.nvim_buf_add_highlight, float_buf, -1, "SuperMarkdownH2", 0, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, float_buf, -1, "SuperMarkdownDivider", 1, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, float_buf, -1, "SuperMarkdownDivider", 3, 0, -1)

  local function close_matrix()
    M.close()
  end

  local function jump_target()
    local cur_row = vim.api.nvim_win_get_cursor(float_win)[1]
    local tgt = line_to_target[cur_row]
    if tgt then
      close_matrix()
      if tgt.file then
        vim.cmd("edit " .. vim.fn.fnameescape(tgt.file))
        vim.api.nvim_win_set_cursor(0, { tgt.lnum or 1, 0 })
      elseif tgt.bufnr then
        vim.api.nvim_set_current_buf(tgt.bufnr)
        vim.api.nvim_win_set_cursor(0, { tgt.lnum or 1, 0 })
        vim.cmd("normal! zvzz")
      end
    end
  end

  local bopts = { buffer = float_buf, nowait = true, silent = true, noremap = true }
  vim.keymap.set("n", "q", close_matrix, bopts)
  vim.keymap.set("n", "<Esc>", close_matrix, bopts)
  vim.keymap.set("n", "<CR>", jump_target, bopts)
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
