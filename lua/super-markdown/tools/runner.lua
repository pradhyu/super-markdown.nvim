local M = {}

local NS_RUNNER = vim.api.nvim_create_namespace("super_markdown_runner")

--- Find the fenced code block containing `cursor_lnum` (1-indexed)
--- @param bufnr number
--- @param cursor_lnum number|nil
--- @return table|nil block { lang, start_lnum, end_lnum, code, lines }
function M.get_block_at_cursor(bufnr, cursor_lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  cursor_lnum = cursor_lnum or vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local in_block = false
  local b_start = nil
  local b_lang = nil
  local b_lines = {}

  for i, line in ipairs(lines) do
    local lang = line:match("^%s*```+([%w_%-%+]*)") or line:match("^%s*~~~+([%w_%-%+]*)")
    if lang then
      if not in_block then
        in_block = true
        b_start = i
        b_lang = vim.trim(lang):lower()
        b_lines = {}
      else
        local b_end = i
        if cursor_lnum >= b_start and cursor_lnum <= b_end then
          return {
            lang = b_lang,
            start_lnum = b_start,
            end_lnum = b_end,
            lines = b_lines,
            code = table.concat(b_lines, "\n"),
          }
        end
        in_block = false
        b_start = nil
        b_lang = nil
        b_lines = {}
      end
    elseif in_block then
      table.insert(b_lines, line)
    end
  end

  return nil
end

--- Render execution output as virtual lines directly below a code block
--- @param bufnr number
--- @param end_lnum number 1-indexed closing fence line
--- @param status_ok boolean
--- @param out_lines string[]
--- @param elapsed_ms number
function M.render_result(bufnr, end_lnum, status_ok, out_lines, elapsed_ms)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Clear any previous runner extmark on this line
  local existing = vim.api.nvim_buf_get_extmarks(bufnr, NS_RUNNER, { end_lnum - 1, 0 }, { end_lnum - 1, -1 }, {})
  for _, em in ipairs(existing) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_RUNNER, em[1])
  end

  local badge_hl = status_ok and "SuperMarkdownCheckboxChecked" or "SuperMarkdownCheckboxImportant"
  local border_hl = "SuperMarkdownCodeBorder"
  local text_hl = status_ok and "SuperMarkdownH2" or "SuperMarkdownCalloutCaution"
  local icon = status_ok and "󰄵 PASS" or "󰀦 FAIL"

  local virt_lines = {
    {
      { "  ├─ ", border_hl },
      { string.format("%s (%dms)", icon, elapsed_ms or 0), badge_hl },
    },
  }

  local max_lines = 15
  for idx, l in ipairs(out_lines) do
    if idx > max_lines then
      table.insert(virt_lines, {
        { "  │ ", border_hl },
        { string.format("... (%d more lines)", #out_lines - max_lines), border_hl },
      })
      break
    end
    table.insert(virt_lines, {
      { "  │ ", border_hl },
      { l, text_hl },
    })
  end

  table.insert(virt_lines, {
    { "  ╰────────────────────────────────────────", border_hl },
  })

  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_RUNNER, end_lnum - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 80,
  })
end

--- Execute the fenced code block under cursor and display inline results
--- @param bufnr number|nil
--- @param cursor_lnum number|nil
function M.run_block(bufnr, cursor_lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local block = M.get_block_at_cursor(bufnr, cursor_lnum)
  if not block then
    vim.notify("SuperMarkdown: Cursor is not inside a fenced code block", vim.log.levels.WARN)
    return nil
  end

  local lang = block.lang
  local t0 = vim.uv.hrtime()

  -- 1. In-process Lua execution (captures print() and return values)
  if lang == "lua" then
    local captured = {}
    local orig_print = _G.print
    _G.print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        table.insert(parts, tostring(select(i, ...)))
      end
      table.insert(captured, table.concat(parts, "\t"))
    end

    local fn, load_err = loadstring(block.code)
    local ok, ret = false, nil
    if fn then
      ok, ret = pcall(fn)
    else
      ok = false
      ret = load_err
    end
    _G.print = orig_print

    if not ok then
      table.insert(captured, tostring(ret))
    elseif ret ~= nil then
      table.insert(captured, "=> " .. vim.inspect(ret))
    end
    if #captured == 0 then
      table.insert(captured, "(Executed cleanly with no stdout)")
    end

    local elapsed = math.floor((vim.uv.hrtime() - t0) / 1e6)
    M.render_result(bufnr, block.end_lnum, ok, captured, elapsed)
    return { ok = ok, output = captured, elapsed_ms = elapsed }
  end

  -- 2. External language runners (bash/sh/zsh, python, javascript/node)
  local runners = {
    bash = { "bash", "-c", block.code },
    sh = { "sh", "-c", block.code },
    zsh = { "zsh", "-c", block.code },
    python = { "python3", "-c", block.code },
    py = { "python3", "-c", block.code },
    javascript = { "node", "-e", block.code },
    js = { "node", "-e", block.code },
  }

  local cmd = runners[lang]
  if not cmd then
    vim.notify("SuperMarkdown: Unsupported runnable block language '" .. tostring(lang) .. "'", vim.log.levels.WARN)
    return nil
  end

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      local elapsed = math.floor((vim.uv.hrtime() - t0) / 1e6)
      local combined = (res.stdout or "") .. (res.stderr or "")
      combined = combined:gsub("\r\n", "\n"):gsub("\n$", "")
      local out_lines = combined ~= "" and vim.split(combined, "\n", { plain = true }) or { "(Done)" }
      M.render_result(bufnr, block.end_lnum, res.code == 0, out_lines, elapsed)
    end)
  end)

  return { async = true, lang = lang }
end

--- Clear all inline code execution results in buffer
--- @param bufnr number|nil
function M.clear_results(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS_RUNNER, 0, -1)
    vim.notify("SuperMarkdown: Cleared code block execution output", vim.log.levels.INFO)
  end
end

function M.get_namespace()
  return NS_RUNNER
end

return M
