local config = require("super-markdown.config")
local highlights = require("super-markdown.highlights")
local render = require("super-markdown.render")
local mermaid = require("super-markdown.mermaid")
local toc_picker = require("super-markdown.toc.picker")
local toc_sidebar = require("super-markdown.toc.sidebar")
local checkbox = require("super-markdown.tools.checkbox")
local list = require("super-markdown.tools.list")
local table_tool = require("super-markdown.tools.table")
local link_tool = require("super-markdown.tools.link")
local runner = require("super-markdown.tools.runner")
local folds = require("super-markdown.folds")
local spec = require("super-markdown.spec")
local llm = require("super-markdown.llm")

local M = {}

function M.setup(user_opts)
  config.setup(user_opts)
  highlights.setup()

  -- Register global autocommands
  local augroup = vim.api.nvim_create_augroup("SuperMarkdownGlobal", { clear = true })

  -- Register mermaid in vim markdown_fenced_languages
  local fenced = vim.g.markdown_fenced_languages or {}
  local has_mmd = false
  for _, l in ipairs(fenced) do
    if l == "mermaid" or l == "mmd=mermaid" then
      has_mmd = true
      break
    end
  end
  if not has_mmd then
    table.insert(fenced, "mermaid")
    vim.g.markdown_fenced_languages = fenced
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = config.options.filetypes,
    callback = function(args)
      local bufnr = args.buf

      -- Attach in-buffer renderer
      if config.options.render.enabled then
        render.attach(bufnr)
      end

      -- Attach markdown folding (+ and - in gutter)
      if config.options.folds and config.options.folds.enabled ~= false then
        folds.attach(bufnr)
      end

      -- Render mermaid block status indicators
      if config.options.mermaid.enabled then
        mermaid.render_status(bufnr)
        vim.api.nvim_create_autocmd({ "TextChanged", "BufEnter" }, {
          buffer = bufnr,
          callback = function()
            mermaid.render_status(bufnr)
          end,
        })
      end

      -- Attach buffer-local keymaps
      M.setup_buffer_keymaps(bufnr)

      -- Optional auto-lint on write
      if config.options.spec and config.options.spec.auto_lint then
        vim.api.nvim_create_autocmd("BufWritePost", {
          buffer = bufnr,
          callback = function()
            require("super-markdown.spec.analyzer").lint(bufnr, true)
          end,
        })
      end
    end,
  })

  -- Refresh highlights on ColorScheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      highlights.setup()
    end,
  })
end

function M.setup_buffer_keymaps(bufnr)
  local km = config.options.keymaps
  local function bmap(mode, lhs, rhs, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = "SuperMarkdown: " .. desc })
    end
  end

  bmap("n", km.toggle_render, M.toggle, "Toggle in-buffer render")
  bmap("n", km.toc, M.toc, "Table of Contents (Picker)")
  bmap("n", km.toc_sidebar, M.toc_sidebar, "Table of Contents (Sidebar)")
  bmap("n", km.mermaid_preview, M.mermaid_preview, "Mermaid Diagram Preview")
  bmap("n", km.toggle_checkbox, M.checkbox_toggle, "Toggle Checkbox")
  bmap("n", km.format_table, M.table_format, "Format Markdown Table")
  bmap("n", km.follow_link, M.follow_link, "Follow Markdown Link")
  bmap("n", km.preview_ref, M.preview_ref, "Preview Linked Code Reference")
  bmap("n", km.fold_all, M.fold_all, "Fold all sections")
  bmap("n", km.unfold_all, M.unfold_all, "Unfold all sections")
  bmap("n", km.fold_toggle, M.fold_toggle, "Toggle fold under cursor")
  bmap("n", km.spec_dashboard, M.spec_dashboard, "Spec Health & Traceability Dashboard")
  bmap("n", km.spec_pick, M.spec_pick, "Semantic Spec Element Picker")
  bmap("n", km.spec_lint, M.spec_lint, "Lint Spec for Ambiguity & Completeness")
  bmap("n", km.spec_new, M.spec_new, "Insert Spec Template")
  bmap("n", km.spec_status, M.spec_status, "Cycle Spec Document Status")
  bmap("n", km.llm_context, M.llm_context, "Copy Section LLM Context Bundle")
  bmap("n", km.llm_code, M.llm_code, "Generate LLM Implementation Prompt")
  bmap("n", km.llm_tests, M.llm_tests, "Generate LLM Test Suite Prompt")
  bmap("n", km.llm_review, M.llm_review, "Generate LLM Spec Review Prompt")
  bmap("n", km.run_block, M.run_block, "Execute Code Block Inline")

  if config.options.tools.table_helpers then
    bmap({ "n", "i" }, km.table_next, table_tool.next_cell, "Next Table Cell")
    bmap({ "n", "i" }, km.table_prev, table_tool.prev_cell, "Previous Table Cell")
  end

  if config.options.folds and config.options.folds.enter_toggle ~= false then
    vim.keymap.set("n", "<CR>", function()
      local ref = link_tool.get_reference_at(bufnr)
      if ref then
        link_tool.follow()
      elseif not folds.handle_normal_enter() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
      end
    end, { buffer = bufnr, silent = true, desc = "SuperMarkdown: Toggle Header Fold or Follow Link" })
  end

  if config.options.tools.smart_lists then
    vim.keymap.set("i", "<CR>", function()
      if not list.handle_enter() then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
      end
    end, { buffer = bufnr, silent = true, desc = "SuperMarkdown: Smart List Enter" })
  end
end

function M.reload()
  pcall(function()
    if toc_sidebar.is_open() then
      toc_sidebar.close()
    end
  end)

  for k, _ in pairs(package.loaded) do
    if k:find("^super%-markdown") then
      package.loaded[k] = nil
    end
  end

  vim.g.loaded_super_markdown = nil
  pcall(vim.cmd, "runtime! plugin/super-markdown.lua")

  local reloaded = require("super-markdown")
  reloaded.setup({})

  -- Re-attach render, folds, and keymaps to all existing markdown buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "markdown" or ft == "md" or ft == "markdown.mdx" then
        require("super-markdown.render").attach(buf)
        require("super-markdown.folds").attach(buf)
        reloaded.setup_buffer_keymaps(buf)
      elseif ft == "supermarkdown_toc" then
        vim.keymap.set("n", "q", function()
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end, { buffer = buf, nowait = true, noremap = true, silent = true })
      end
    end
  end

  vim.notify("SuperMarkdown: All modules, folds & keymaps reloaded 󰑐", vim.log.levels.INFO)
end

-- Public API
M.toggle = render.toggle
M.render = render.render
M.clear = render.clear
M.toc = toc_picker.open
M.toc_sidebar = toc_sidebar.toggle
M.mermaid_preview = mermaid.preview_under_cursor
M.checkbox_toggle = checkbox.toggle
M.table_format = table_tool.format
M.follow_link = link_tool.follow
M.preview_ref = link_tool.preview
M.fold_all = folds.fold_all
M.fold_toc = folds.fold_toc
M.unfold_all = folds.unfold_all
M.fold_toggle = folds.toggle_fold
M.fold_level = folds.fold_level
M.spec_dashboard = spec.dashboard
M.spec_pick = spec.pick
M.spec_lint = spec.lint
M.spec_clear_lint = spec.clear_lint
M.spec_new = spec.new_spec
M.spec_status = spec.cycle_status
M.llm_context = llm.copy_context
M.llm_code = llm.generate_code
M.llm_tests = llm.generate_tests
M.llm_review = llm.review_spec
M.run_block = runner.run_block
M.clear_runs = runner.clear_results

return M
