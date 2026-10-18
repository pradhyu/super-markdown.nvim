local toc = require("super-markdown.toc")

local M = {}

function M.open(opts)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false, "Telescope is not installed"
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local entry_display = require("telescope.pickers.entry_display")

  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local headings = toc.get_headings(bufnr)

  if #headings == 0 then
    vim.notify("SuperMarkdown: No headings found in buffer", vim.log.levels.WARN)
    return true
  end

  local max_len = 20
  for _, h in ipairs(headings) do
    if #h.display > max_len then
      max_len = #h.display
    end
  end
  local col_width = math.min(math.max(max_len + 2, 40), 80)

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = col_width },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    local h = entry.value
    return displayer({
      { h.display, "SuperMarkdownH" .. h.level },
      { string.format("[L%d]", h.lnum), "Comment" },
    })
  end

  local finder = finders.new_table({
    results = headings,
    entry_maker = function(heading)
      return {
        value = heading,
        display = make_display,
        ordinal = heading.title,
        filename = filename,
        bufnr = bufnr,
        lnum = heading.lnum,
        col = 1,
      }
    end,
  })

  local ns_previewer = vim.api.nvim_create_namespace("super_markdown_telescope_preview")

  local previewer = previewers.new_buffer_previewer({
    title = "Heading Preview",
    get_buffer_by_name = function(_, entry)
      return (entry.filename and entry.filename ~= "") and entry.filename or tostring(entry.bufnr or bufnr)
    end,
    teardown = function(self)
      if self.state and self.state.bufnr and vim.api.nvim_buf_is_valid(self.state.bufnr) then
        pcall(vim.api.nvim_buf_clear_namespace, self.state.bufnr, ns_previewer, 0, -1)
      end
    end,
    define_preview = function(self, entry)
      local target_buf = entry.bufnr or bufnr
      local target_file = entry.filename

      local function jump_to_line(pbufnr)
        if not (self.state and self.state.winid and vim.api.nvim_win_is_valid(self.state.winid)) then
          return
        end
        if not (pbufnr and vim.api.nvim_buf_is_valid(pbufnr)) then
          return
        end

        pcall(vim.api.nvim_buf_clear_namespace, pbufnr, ns_previewer, 0, -1)

        if entry.lnum and entry.lnum > 0 then
          pcall(vim.api.nvim_buf_set_extmark, pbufnr, ns_previewer, entry.lnum - 1, 0, {
            end_row = entry.lnum,
            hl_group = "TelescopePreviewLine",
            hl_eol = true,
          })
          pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, 0 })
          vim.api.nvim_win_call(self.state.winid, function()
            vim.cmd("normal! zz")
          end)
        end
      end

      if target_buf and vim.api.nvim_buf_is_valid(target_buf) and (not target_file or target_file == "" or vim.bo[target_buf].modified) then
        local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        local ft = vim.bo[target_buf].filetype
        if ft and ft ~= "" then
          pcall(function()
            vim.bo[self.state.bufnr].filetype = ft
          end)
        end
        vim.schedule(function()
          jump_to_line(self.state.bufnr)
        end)
      else
        conf.buffer_previewer_maker(target_file, self.state.bufnr, {
          bufname = self.state.bufname,
          winid = self.state.winid,
          callback = function(pbufnr)
            vim.schedule(function()
              jump_to_line(pbufnr)
            end)
          end,
        })
      end
    end,
  })

  opts = opts or {}
  local user_attach = opts.attach_mappings

  local picker_opts = vim.tbl_deep_extend("force", {
    prompt_title = " 󰲡 Markdown Table of Contents ",
    finder = finder,
    sorter = conf.generic_sorter(opts),
    previewer = previewer,
    default_selection_index = 1,
    sorting_strategy = "ascending",
    layout_config = {
      prompt_position = "top",
    },
    tiebreak = function(current_entry, existing_entry, _)
      return (current_entry.lnum or 0) < (existing_entry.lnum or 0)
    end,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          vim.api.nvim_win_set_cursor(0, { selection.value.lnum, 0 })
          vim.cmd("normal! zvzz")
        end
      end)
      if user_attach then
        return user_attach(prompt_bufnr, map)
      end
      return true
    end,
  }, opts)

  pickers.new(picker_opts):find()

  return true
end

return M
