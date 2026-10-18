local M = {}

function M.follow()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum, col = cursor[1], cursor[2] + 1
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  local search_pos = 1
  while true do
    local s_start, s_end, text, target = line:find("%[([^%]]+)%]%(([^%)]+)%)", search_pos)
    if not s_start then break end

    if col >= s_start and col <= s_end then
      local clean_target = vim.trim(target)

      -- 1. Web URL
      if clean_target:match("^https?://") or clean_target:match("^mailto:") then
        vim.ui.open(clean_target)
        vim.notify("SuperMarkdown: Opening web link: " .. clean_target, vim.log.levels.INFO)
        return
      end

      -- 2. Local file
      local current_file = vim.api.nvim_buf_get_name(bufnr)
      local current_dir = vim.fs.dirname(current_file) or "."
      local resolved_path = vim.fs.normalize(current_dir .. "/" .. clean_target)

      if vim.fn.filereadable(resolved_path) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(resolved_path))
      elseif vim.fn.filereadable(clean_target) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(clean_target))
      else
        -- If doesn't exist, ask to create it
        vim.ui.input({ prompt = "File does not exist. Create? (y/n): " }, function(input)
          if input and input:lower() == "y" then
            local p_dir = vim.fs.dirname(resolved_path)
            if p_dir and vim.fn.isdirectory(p_dir) == 0 then
              vim.fn.mkdir(p_dir, "p")
            end
            vim.cmd("edit " .. vim.fn.fnameescape(resolved_path))
          end
        end)
      end
      return
    end

    search_pos = s_end + 1
  end

  vim.notify("SuperMarkdown: No markdown link under cursor", vim.log.levels.WARN)
end

return M
