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
local preview_pane = require("super-markdown.preview_pane")
local focus = require("super-markdown.focus")
local spec_diff = require("super-markdown.spec.diff")
local spec_nav = require("super-markdown.spec.navigation")
local spec_review = require("super-markdown.spec.review")
local breadcrumb = require("super-markdown.render.breadcrumb")
local zen = require("super-markdown.zen")
local skim = require("super-markdown.skim")
local eyeball = require("super-markdown.spec.eyeball")
local statusline = require("super-markdown.statusline")
local sticky = require("super-markdown.sticky")

local M = {}

local function purge_buffer_autocmds(bufnr)
  pcall(vim.api.nvim_create_augroup, "SuperMarkdownBuf_" .. bufnr, { clear = true })
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { buffer = bufnr })
  if not ok or type(autocmds) ~= "table" then
    return
  end
  for _, ac in ipairs(autocmds) do
    if not ac.group and ac.id and type(ac.callback) == "function" then
      local ok_info, info = pcall(debug.getinfo, ac.callback, "S")
      if ok_info and info and info.source and info.source:find("super%-markdown") then
        pcall(vim.api.nvim_del_autocmd, ac.id)
      end
    end
  end
end

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
      purge_buffer_autocmds(bufnr)
      local buf_group = vim.api.nvim_create_augroup("SuperMarkdownBuf_" .. bufnr, { clear = true })

      -- Attach in-buffer renderer
      if config.options.render.enabled then
        render.attach(bufnr)
      end

      -- Attach focus mode (active block spotlight & dimming)
      focus.attach(bufnr)

      -- Attach markdown folding (+ and - in gutter)
      if config.options.folds and config.options.folds.enabled ~= false then
        folds.attach(bufnr)
      end

      -- Attach sticky stacked headers
      sticky.attach(bufnr)

      -- Render mermaid block status indicators when full buffer render is disabled
      if config.options.mermaid.enabled and not config.options.render.enabled then
        mermaid.render_status(bufnr)
        vim.api.nvim_create_autocmd({ "TextChanged", "BufEnter" }, {
          group = buf_group,
          buffer = bufnr,
          callback = function()
            mermaid.render_status(bufnr)
          end,
        })
      end

      -- Attach buffer-local keymaps
      M.setup_buffer_keymaps(bufnr)

      -- Start interval auto-refresh for external/AI file changes if enabled
      if preview_pane.is_auto_refresh_enabled() then
        preview_pane.start_auto_refresh()
      end

      -- Auto-format markdown tables when finishing an edit (InsertLeave) or saving (BufWritePre)
      if config.options.tools and config.options.tools.auto_format_table ~= false then
        vim.api.nvim_create_autocmd("InsertLeave", {
          group = buf_group,
          buffer = bufnr,
          callback = function()
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable then
              table_tool.format({ bufnr = bufnr, silent = true })
            end
          end,
        })
        vim.api.nvim_create_autocmd("BufWritePre", {
          group = buf_group,
          buffer = bufnr,
          callback = function()
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable then
              table_tool.format_all({ bufnr = bufnr, silent = true })
            end
          end,
        })
      end

      -- Optional auto-lint on write
      if config.options.spec and config.options.spec.auto_lint then
        vim.api.nvim_create_autocmd("BufWritePost", {
          group = buf_group,
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
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = "SuperMarkdown: " .. desc })
    end
  end

  bmap("n", km.toggle_render, M.toggle, "Toggle in-buffer render")
  bmap("n", km.toggle_focus, M.focus_toggle, "Toggle Focus Mode (Highlight Active Block, Dim Others)")
  bmap("n", km.toggle_skim, M.skim_toggle, "Toggle Executive Skim Mode (Prose Dimmer)")
  bmap("n", km.toggle_sticky, M.sticky_toggle, "Toggle Sticky Stacked Headers (Context Stack at Window Top)")
  bmap("n", km.toggle_scroll_to_top, M.toggle_scroll_to_top, "Toggle TOC Scroll to Top (zt ↔ zz)")
  bmap("n", km.eyeball, M.eyeball, "Open Agent Spec Eyeballer & Scorecard HUD")
  bmap("n", km.toggle_zen, M.zen, "Toggle Reading Focus Zoom (Maximize Buffer Width)")
  bmap("n", km.preview_pane, M.preview_pane, "Toggle Live Read-Only Side Preview Pane")
  bmap("n", km.toggle_editor, M.toggle_editor, "Toggle Edit Mode Split Visibility (Hide/Show Editor)")
  bmap("n", km.reader_mode, M.reader_mode, "Enter Reader Mode (Hide Editor + Open Preview & TOC Sidebar)")
  bmap("n", km.auto_refresh, M.auto_refresh, "Toggle Interval Auto-Refresh (Disk / Visual / Preview / Sidebar)")
  bmap("n", km.toc, M.toc, "Table of Contents (Picker)")
  bmap("n", km.toc_sidebar, M.toc_sidebar, "Table of Contents (Sidebar)")
  bmap("n", km.mermaid_preview, M.mermaid_preview, "Mermaid Diagram Preview")
  bmap("n", km.toggle_checkbox, M.checkbox_toggle, "Toggle Checkbox")
  bmap("n", km.format_table, M.table_format, "Format Markdown Table")
  bmap("n", km.follow_link, M.follow_link, "Follow Markdown Link")
  bmap("n", km.preview_ref, M.preview_ref, "Preview Linked Code Reference")
  bmap("n", km.fold_all, M.collapse_all, "Fold all sections across views")
  bmap("n", km.unfold_all, M.expand_all, "Unfold all sections across views")
  bmap("n", km.fold_toggle, M.toggle_header, "Toggle fold under cursor across views")
  bmap("n", "za", M.toggle_header, "Toggle fold under cursor across views")
  bmap("n", "zc", M.collapse_header, "Collapse fold under cursor across views")
  bmap("n", "zo", M.expand_header, "Expand fold under cursor across views")
  bmap("n", "zM", M.collapse_all, "Collapse all sections across views")
  bmap("n", "zR", M.expand_all, "Expand all sections across views")
  bmap("n", "zm", M.fold_more, "Fold more across views")
  bmap("n", "zr", M.fold_less, "Fold less across views")
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
  bmap("n", km.diff_toggle, M.diff_toggle, "Toggle Git Spec Change Highlights")
  bmap("n", km.diff_dashboard, M.diff_dashboard, "Open Agent Spec Changes Eyeballer HUD")
  bmap("n", km.next_change, M.next_change, "Jump to Next Changed Line")
  bmap("n", km.prev_change, M.prev_change, "Jump to Previous Changed Line")
  bmap("n", km.next_requirement, M.next_requirement, "Jump to Next Requirement (REQ-*/AC-*)")
  bmap("n", km.prev_requirement, M.prev_requirement, "Jump to Previous Requirement (REQ-*/AC-*)")
  bmap("n", km.next_question, M.next_question, "Jump to Next Open Question")
  bmap("n", km.prev_question, M.prev_question, "Jump to Previous Open Question")
  bmap("n", km.next_blocker, M.next_blocker, "Jump to Next Blocker")
  bmap("n", km.prev_blocker, M.prev_blocker, "Jump to Previous Blocker")
  bmap("n", km.next_task, M.next_task, "Jump to Next Pending Task")
  bmap("n", km.prev_task, M.prev_task, "Jump to Previous Pending Task")
  bmap("n", km.next_risk, M.next_risk, "Jump to Next Critical Risk / Hazard")
  bmap("n", km.prev_risk, M.prev_risk, "Jump to Previous Critical Risk / Hazard")
  bmap("n", km.next_fluff, M.next_fluff, "Jump to Next Ambiguity / AI Fluff")
  bmap("n", km.prev_fluff, M.prev_fluff, "Jump to Previous Ambiguity / AI Fluff")
  bmap("n", km.next_scenario, M.next_scenario, "Jump to Next Acceptance Criteria / BDD Scenario")
  bmap("n", km.prev_scenario, M.prev_scenario, "Jump to Previous Acceptance Criteria / BDD Scenario")
  bmap("n", km.next_review, M.next_review, "Jump to Next Human Review Directive")
  bmap("n", km.prev_review, M.prev_review, "Jump to Previous Human Review Directive")
  bmap("n", km.review_approve, M.review_approve, "Approve Section as Human Reviewer")
  bmap("n", km.review_question, M.review_question, "Leave Question/Directive for AI Agent")
  bmap("n", km.review_reject, M.review_reject, "Request Revision from AI Agent")
  bmap("n", km.review_comment, M.review_comment, "Add Inline Human Review Comment")
  bmap("n", km.review_approve_all, M.review_approve_all, "Mark Entire Spec APPROVED")
  bmap("n", km.review_reject_all, M.review_reject_all, "Request Changes on Entire Spec")
  bmap("n", km.review_export, M.review_export, "Export Agent Review Feedback Prompt")
  bmap("n", km.breadcrumb, M.breadcrumb, "Show Active Breadcrumb & Stats HUD")

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
    preview_pane.stop_auto_refresh()
    if toc_sidebar.is_open() then
      toc_sidebar.close()
    end
    if preview_pane.is_open() then
      preview_pane.close()
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
        purge_buffer_autocmds(buf)
        pcall(vim.api.nvim_buf_clear_namespace, buf, vim.api.nvim_create_namespace("super_markdown_render"), 0, -1)
        pcall(vim.api.nvim_buf_clear_namespace, buf, vim.api.nvim_create_namespace("super_markdown_mermaid"), 0, -1)
        require("super-markdown.render").attach(buf)
        require("super-markdown.folds").attach(buf)
        require("super-markdown.focus").attach(buf)
        reloaded.setup_buffer_keymaps(buf)
      elseif ft == "supermarkdown_toc" then
        vim.keymap.set("n", "q", function()
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end, { buffer = buf, nowait = true, noremap = true, silent = true })
      end
    end
  end
  pcall(function()
    local pp = require("super-markdown.preview_pane")
    if pp.is_auto_refresh_enabled() then
      pp.start_auto_refresh()
    end
  end)

  vim.notify("SuperMarkdown: All modules, folds & keymaps reloaded 󰑐", vim.log.levels.INFO)
end

-- Public API
M.toggle = render.toggle
M.preview_pane = preview_pane.toggle
M.preview_open = preview_pane.open
M.preview_close = preview_pane.close
M.preview_sync = preview_pane.set_sync
M.auto_refresh = preview_pane.set_auto_refresh
M.toggle_editor = preview_pane.toggle_editor
M.hide_editor = preview_pane.hide_editor
M.show_editor = preview_pane.show_editor
M.reader_mode = preview_pane.reader_mode
M.render = render.render
M.clear = render.clear
M.toc = toc_picker.open
M.toc_sidebar = toc_sidebar.toggle
M.toc_sidebar_pos = toc_sidebar.set_position
M.mermaid_preview = mermaid.preview_under_cursor
M.set_mermaid_renderer = mermaid.set_renderer
M.get_mermaid_renderer = mermaid.get_active_renderer
M.checkbox_toggle = checkbox.toggle
M.table_format = table_tool.format
M.follow_link = link_tool.follow
M.preview_ref = link_tool.preview
M.fold_all = folds.collapse_all
M.fold_toc = folds.collapse_all
M.unfold_all = folds.expand_all
M.fold_toggle = folds.toggle_header
M.collapse_all = folds.collapse_all
M.expand_all = folds.expand_all
M.collapse_header = folds.collapse_header
M.expand_header = folds.expand_header
M.toggle_header = folds.toggle_header
M.fold_more = folds.fold_more
M.fold_less = folds.fold_less
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
M.focus_toggle = focus.toggle
M.focus_enable = focus.enable
M.focus_disable = focus.disable
M.focus_block = focus.get_block_range
M.is_focus_enabled = focus.is_enabled
M.diff_toggle = spec_diff.toggle
M.diff_render = spec_diff.render
M.diff_clear = spec_diff.clear
M.diff_dashboard = spec_diff.open_diff_dashboard
M.next_change = spec_nav.jump_next_change
M.prev_change = spec_nav.jump_prev_change
M.next_requirement = spec_nav.jump_next_requirement
M.prev_requirement = spec_nav.jump_prev_requirement
M.next_question = spec_nav.jump_next_question
M.prev_question = spec_nav.jump_prev_question
M.next_blocker = spec_nav.jump_next_blocker
M.prev_blocker = spec_nav.jump_prev_blocker
M.next_task = spec_nav.jump_next_task
M.prev_task = spec_nav.jump_prev_task
M.review_approve = spec_review.review_approve
M.review_question = spec_review.review_question
M.review_reject = spec_review.review_reject
M.review_comment = spec_review.review_comment
M.review_approve_all = spec_review.review_approve_all
M.review_reject_all = spec_review.review_reject_all
M.review_export = spec_review.review_export
M.review_summary = spec_review.get_review_summary
M.next_risk = spec_nav.jump_next_risk
M.prev_risk = spec_nav.jump_prev_risk
M.next_fluff = spec_nav.jump_next_ambiguity
M.prev_fluff = spec_nav.jump_prev_ambiguity
M.next_scenario = spec_nav.jump_next_scenario
M.prev_scenario = spec_nav.jump_prev_scenario
M.next_review = spec_nav.jump_next_review_note
M.prev_review = spec_nav.jump_prev_review_note
M.skim = skim.toggle
M.skim_toggle = skim.toggle
M.skim_enable = skim.enable
M.skim_disable = skim.disable
M.is_skim_enabled = skim.is_enabled
M.eyeball = eyeball.open
M.eyeball_hud = eyeball.open
M.breadcrumb = breadcrumb.show_hud
M.zen = zen.toggle
M.statusline = statusline.get_status
M.sticky = sticky.toggle
M.sticky_toggle = sticky.toggle
M.sticky_enable = sticky.enable
M.sticky_disable = sticky.disable
M.is_sticky_enabled = sticky.is_enabled
M.set_scroll_to_top = toc_sidebar.set_scroll_to_top
M.is_scroll_to_top = toc_sidebar.is_scroll_to_top
M.toggle_scroll_to_top = function() toc_sidebar.set_scroll_to_top("toggle") end

return M
