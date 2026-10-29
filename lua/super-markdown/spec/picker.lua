local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local KIND_LABELS = {
  question = { badge = "QUESTION", hl = "SuperMarkdownCheckboxQuestion" },
  blocker  = { badge = "BLOCKER ", hl = "SuperMarkdownCheckboxImportant" },
  task     = { badge = "TASK    ", hl = "SuperMarkdownCheckboxProgress" },
  requirement = { badge = "REQ     ", hl = "SuperMarkdownH3" },
  diagram  = { badge = "DIAGRAM ", hl = "SuperMarkdownMermaidReady" },
  table    = { badge = "TABLE   ", hl = "SuperMarkdownTableHeader" },
  callout  = { badge = "ALERT   ", hl = "SuperMarkdownCalloutWarning" },
  ref      = { badge = "TRACE   ", hl = "SuperMarkdownLink" },
}

--- Get filtered semantic spec items from buffer
--- @param bufnr number
--- @param filter_kind string|nil Optional kind filter ("question", "blocker", "task", "requirement", "diagram", "table", "ref")
--- @return table[] items
function M.get_items(bufnr, filter_kind)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local analysis = analyzer.analyze(bufnr)
  local items = {}

  for _, item in ipairs(analysis.items) do
    if not filter_kind or filter_kind == "" or filter_kind == "all" or item.kind == filter_kind then
      local meta = KIND_LABELS[item.kind] or { badge = item.kind:upper(), hl = "SuperMarkdownH2" }
      item.badge = meta.badge
      item.hl = meta.hl
      item.display = string.format("%s [%s] %s  (%s · L%d)", item.icon, meta.badge, item.text, item.section, item.lnum)
      table.insert(items, item)
    end
  end

  return items
end

--- Open Semantic Spec Picker via Telescope, Snacks, or vim.ui.select
--- @param filter_kind string|nil
function M.open(filter_kind)
  local bufnr = vim.api.nvim_get_current_buf()
  local items = M.get_items(bufnr, filter_kind)

  if #items == 0 then
    local suffix = filter_kind and (" matching '" .. filter_kind .. "'") or ""
    vim.notify("SuperMarkdown: No semantic spec elements found" .. suffix, vim.log.levels.INFO)
    return
  end

  local has_telescope, pickers = pcall(require, "telescope.pickers")
  if has_telescope then
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")

    local filename = vim.api.nvim_buf_get_name(bufnr)
    local title = "SuperMarkdown Spec Explorer" .. (filter_kind and (" (" .. filter_kind .. ")") or "")

    pickers.new({}, {
      prompt_title = title,
      sorting_strategy = "ascending",
      default_selection_index = 1,
      layout_config = {
        prompt_position = "top",
      },
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
            filename = filename,
            bufnr = bufnr,
            lnum = entry.lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Spec Context Preview",
        define_preview = function(self, entry)
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
          vim.schedule(function()
            if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
              pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, 0 })
              pcall(vim.api.nvim_win_call, self.state.winid, function()
                vim.cmd("normal! zz")
              end)
            end
          end)
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            vim.api.nvim_win_set_cursor(0, { selection.value.lnum, 0 })
            vim.cmd("normal! zvzz")
          end
        end)
        return true
      end,
    }):find()
    return
  end

  -- Fallback to vim.ui.select
  vim.ui.select(items, {
    prompt = "Spec Elements" .. (filter_kind and (" [" .. filter_kind .. "]:") or ":"),
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      vim.api.nvim_win_set_cursor(0, { choice.lnum, 0 })
      vim.cmd("normal! zvzz")
    end
  end)
end

return M
