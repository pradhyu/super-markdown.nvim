local config = require("super-markdown.config")
local headings = require("super-markdown.render.headings")
local checkboxes = require("super-markdown.render.checkboxes")
local callouts = require("super-markdown.render.callouts")
local tables = require("super-markdown.render.tables")
local codeblocks = require("super-markdown.render.codeblocks")
local divider = require("super-markdown.render.divider")
local links = require("super-markdown.render.links")
local spec_tags = require("super-markdown.render.spec_tags")
local analyzer = require("super-markdown.spec.analyzer")

local mermaid = require("super-markdown.mermaid")

local M = {}

local NS_ID = vim.api.nvim_create_namespace("super_markdown_render")
local buf_states = {} -- bufnr -> { enabled = bool, timer = uv_timer }

function M.get_namespace()
  return NS_ID
end

function M.is_enabled(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if buf_states[bufnr] == nil then
    return config.options.render.enabled
  end
  return buf_states[bufnr].enabled
end

function M.set_enabled(bufnr, state)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not buf_states[bufnr] then
    buf_states[bufnr] = {}
  end
  buf_states[bufnr].enabled = state
  if state then
    M.render(bufnr)
  else
    M.clear(bufnr)
  end
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local current = M.is_enabled(bufnr)
  M.set_enabled(bufnr, not current)
  vim.notify(
    "SuperMarkdown: Rendering " .. (not current and "Enabled 󰄵" or "Disabled 󰄱"),
    vim.log.levels.INFO
  )
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS_ID, 0, -1)
  end
end

function M.render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if not M.is_enabled(bufnr) then return end

  local r_opts = (config.options and config.options.render) or {}

  -- Apply buffer window display settings
  local win = vim.fn.bufwinid(bufnr)
  if win and win ~= -1 then
    pcall(vim.api.nvim_set_option_value, "conceallevel", r_opts.conceallevel or 2, { win = win })
    pcall(vim.api.nvim_set_option_value, "concealcursor", r_opts.concealcursor or "c", { win = win })
  end

  -- Clear previous decorations
  vim.api.nvim_buf_clear_namespace(bufnr, NS_ID, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line_count = #lines

  -- Pre-compute section analysis for heading progress & traceability badges
  local sec_by_lnum = {}
  local ok_an, analysis = pcall(analyzer.analyze, bufnr)
  if ok_an and analysis and analysis.sections then
    for _, sec in ipairs(analysis.sections) do
      sec_by_lnum[sec.lnum] = sec
    end
  end

  local prev_callout = nil
  local in_codeblock = nil
  local lnum = 0

  while lnum < line_count do
    local line = lines[lnum + 1]

    -- 1. Codeblocks
    local was_in_codeblock = in_codeblock ~= nil
    in_codeblock = codeblocks.render(bufnr, NS_ID, lnum, line, in_codeblock, r_opts.codeblocks)

    if not in_codeblock and not was_in_codeblock then
      -- 2. Tables: check if start of a contiguous table block
      if tables.is_table_row(line) then
        local tbl_start = lnum
        local tbl_end = lnum
        while tbl_end + 1 < line_count and tables.is_table_row(lines[tbl_end + 2]) do
          tbl_end = tbl_end + 1
        end

        tables.render_block(bufnr, NS_ID, tbl_start, tbl_end, lines, r_opts.tables)
        lnum = tbl_end + 1
      else
        -- 3. Headings (with spec progress & traceability badges)
        headings.render(bufnr, NS_ID, lnum, line, r_opts.headings, sec_by_lnum[lnum + 1])

        -- 4. Checkboxes
        checkboxes.render(bufnr, NS_ID, lnum, line, r_opts.checkboxes)

        -- 5. Callouts
        prev_callout = callouts.render(bufnr, NS_ID, lnum, line, prev_callout, r_opts.callouts)

        -- 6. Dividers
        divider.render(bufnr, NS_ID, lnum, line, r_opts.dividers)

        -- 7. Links
        links.render(bufnr, NS_ID, lnum, line, r_opts.links)

        -- 8. Spec Tags (@impl, @test, REQ-IDs, Document Status)
        spec_tags.render(bufnr, NS_ID, lnum, line, r_opts.spec_tags)

        lnum = lnum + 1
      end
    else
      lnum = lnum + 1
    end
  end

  -- 8. Render Mermaid diagrams automatically in line
  if config.options.mermaid and config.options.mermaid.enabled ~= false and config.options.mermaid.inline ~= false then
    mermaid.render_inline(bufnr, NS_ID, config.options.mermaid)
  end
end

function M.debounced_render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not buf_states[bufnr] then
    buf_states[bufnr] = { enabled = config.options.render.enabled }
  end

  local state = buf_states[bufnr]
  if state.timer then
    state.timer:stop()
  else
    state.timer = vim.uv.new_timer()
  end

  state.timer:start(
    config.options.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        M.render(bufnr)
      end
    end)
  )
end

function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  M.render(bufnr)

  local group = vim.api.nvim_create_augroup("SuperMarkdownRender_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.debounced_render(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if buf_states[bufnr] and buf_states[bufnr].timer then
        buf_states[bufnr].timer:stop()
        buf_states[bufnr].timer:close()
      end
      buf_states[bufnr] = nil
    end,
  })
end

return M
