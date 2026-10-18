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
local folds = require("super-markdown.folds")

local M = {}

function M.setup(user_opts)
  config.setup(user_opts)
  highlights.setup()

  -- Register global autocommands
  local augroup = vim.api.nvim_create_augroup("SuperMarkdownGlobal", { clear = true })

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
  bmap("n", km.fold_all, M.fold_all, "Fold all sections")
  bmap("n", km.unfold_all, M.unfold_all, "Unfold all sections")
  bmap("n", km.fold_toggle, M.fold_toggle, "Toggle fold under cursor")

  if config.options.tools.table_helpers then
    bmap({ "n", "i" }, km.table_next, table_tool.next_cell, "Next Table Cell")
    bmap({ "n", "i" }, km.table_prev, table_tool.prev_cell, "Previous Table Cell")
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
  local user_opts = vim.deepcopy(config.options)
  for k, _ in pairs(package.loaded) do
    if k:find("^super%-markdown") then
      package.loaded[k] = nil
    end
  end
  local reloaded = require("super-markdown")
  reloaded.setup(user_opts)
  reloaded.render()
  vim.notify("SuperMarkdown: All modules reloaded 󰑐", vim.log.levels.INFO)
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
M.fold_all = folds.fold_all
M.unfold_all = folds.unfold_all
M.fold_toggle = folds.toggle_fold
M.fold_level = folds.fold_level

return M
