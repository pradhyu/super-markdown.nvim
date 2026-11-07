local M = {}

local state = {
  active = false,
  saved_winrestcmd = nil,
  target_win = nil,
}

--- Toggles maximized reading focus (zooms active window to full width, restores on toggle)
function M.toggle()
  local cur_win = vim.api.nvim_get_current_win()

  if state.active and state.target_win == cur_win then
    -- Restore previous split layout
    if state.saved_winrestcmd and state.saved_winrestcmd ~= "" then
      pcall(vim.cmd, state.saved_winrestcmd)
    else
      pcall(vim.cmd, "wincmd =")
    end
    state.active = false
    state.saved_winrestcmd = nil
    state.target_win = nil
    vim.notify("SuperMarkdown: Window layout restored 󰄵", vim.log.levels.INFO)
  else
    -- Save current split configuration and maximize
    state.saved_winrestcmd = vim.fn.winrestcmd()
    state.target_win = cur_win
    state.active = true
    pcall(vim.cmd, "wincmd |")
    vim.notify("SuperMarkdown: Reading Focus Zoomed 󰍔 (press <leader>mz or :SuperMarkdown zen to restore)", vim.log.levels.INFO)
  end
end

function M.is_active()
  return state.active
end

return M
