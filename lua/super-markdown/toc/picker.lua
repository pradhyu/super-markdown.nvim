local config = require("super-markdown.config")
local telescope_toc = require("super-markdown.toc.telescope")
local snacks_toc = require("super-markdown.toc.snacks")
local toc = require("super-markdown.toc")

local M = {}

function M.open(opts)
  local choice = config.options.toc.picker

  if choice == "telescope" then
    local ok, err = telescope_toc.open(opts)
    if not ok then
      vim.notify("SuperMarkdown: " .. (err or "Telescope failed"), vim.log.levels.ERROR)
    end
    return
  elseif choice == "snacks" then
    local ok, err = snacks_toc.open()
    if not ok then
      vim.notify("SuperMarkdown: " .. (err or "Snacks failed"), vim.log.levels.ERROR)
    end
    return
  end

  -- Auto mode: prefer Telescope, then Snacks, then vim.ui.select
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    local ok = telescope_toc.open(opts)
    if ok then return end
  end

  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    local ok = snacks_toc.open()
    if ok then return end
  end

  -- Fallback to vim.ui.select
  M.open_ui_select()
end

function M.open_ui_select()
  local bufnr = vim.api.nvim_get_current_buf()
  local headings = toc.get_headings(bufnr)

  if #headings == 0 then
    vim.notify("SuperMarkdown: No headings found in buffer", vim.log.levels.WARN)
    return
  end

  vim.ui.select(headings, {
    prompt = "Table of Contents:",
    format_item = function(item)
      return string.format("%s (Line %d)", item.display, item.lnum)
    end,
  }, function(choice)
    if choice then
      vim.api.nvim_win_set_cursor(0, { choice.lnum, 0 })
      vim.cmd("normal! zvzz")
    end
  end)
end

return M
