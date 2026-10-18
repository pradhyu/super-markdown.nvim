local config = require("super-markdown.config")
local compiler = require("super-markdown.mermaid.compiler")

local M = {}

local preview_win = nil
local preview_buf = nil

local function is_kitty_terminal()
  return vim.env.KITTY_PID ~= nil or (vim.env.TERM and vim.env.TERM:find("kitty") ~= nil)
end

function M.close()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

function M.open(mermaid_code)
  M.close()

  local p_opts = config.options.mermaid.preview_win
  local width = math.floor(vim.o.columns * (p_opts.width or 0.85))
  local height = math.floor(vim.o.lines * (p_opts.height or 0.85))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  preview_buf = vim.api.nvim_create_buf(false, true)
  preview_win = vim.api.nvim_open_win(preview_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = p_opts.border or "rounded",
    title = " 󰡷 Mermaid Diagram Preview ",
    title_pos = "center",
    footer = " [q] Close | [a] Toggle ASCII | [o] Open External | [r] Recompile ",
    footer_pos = "center",
  })

  -- Set loading message
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {
    "",
    "  󰡷 Compiling Mermaid diagram...",
    "  Please wait a moment.",
  })

  compiler.compile(mermaid_code, function(err, result)
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
      return
    end

    local show_ascii = function()
      local lines = result.ascii or { "No ASCII representation available." }
      vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
      vim.bo[preview_buf].filetype = "markdown"
    end

    local show_image = function()
      if result.png and is_kitty_terminal() and vim.fn.executable("kitty") == 1 then
        -- Open terminal buffer with kitten icat
        local term_cmd = string.format("kitty +kitten icat --align center %s", vim.fn.fnameescape(result.png))
        vim.fn.termopen(term_cmd)
      elseif result.png then
        show_ascii()
        table.insert(result.ascii, "")
        table.insert(result.ascii, "  󰅒 Terminal does not support Kitty protocol. Press [o] to open PNG in system viewer.")
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, result.ascii)
      else
        show_ascii()
      end
    end

    local mode = "image"
    if result.png and is_kitty_terminal() then
      show_image()
    else
      mode = "ascii"
      show_ascii()
    end

    -- Setup keymaps in preview buffer
    local set_keymap = function(key, fn)
      vim.keymap.set("n", key, fn, { buffer = preview_buf, nowait = true, silent = true })
    end

    set_keymap("q", M.close)
    set_keymap("<Esc>", M.close)

    set_keymap("a", function()
      if mode == "image" then
        mode = "ascii"
        show_ascii()
      else
        mode = "image"
        show_image()
      end
    end)

    set_keymap("o", function()
      local target = result.png or result.svg
      if target and vim.fn.filereadable(target) == 1 then
        vim.ui.open(target)
        vim.notify("Opened diagram in external viewer: " .. target, vim.log.levels.INFO)
      else
        vim.notify("No image file available to open", vim.log.levels.WARN)
      end
    end)

    set_keymap("r", function()
      -- Bypass cache by deleting cached files
      if result.png then pcall(os.remove, result.png) end
      if result.svg then pcall(os.remove, result.svg) end
      M.open(mermaid_code)
    end)
  end)
end

return M
