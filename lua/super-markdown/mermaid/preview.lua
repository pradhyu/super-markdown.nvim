local config = require("super-markdown.config")
local compiler = require("super-markdown.mermaid.compiler")
local syntax = require("super-markdown.mermaid.syntax")

local M = {}

local preview_win = nil
local preview_buf = nil
local NS_ID = vim.api.nvim_create_namespace("super_markdown_mermaid_popup")

local function is_kitty_terminal()
  return vim.env.KITTY_PID ~= nil or (vim.env.TERM and vim.env.TERM:find("kitty") ~= nil)
end

function M.close()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    pcall(vim.api.nvim_win_close, preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

local function style_ascii_buffer(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for idx, line in ipairs(lines) do
    local lnum = idx - 1
    if idx == 1 then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_ID, lnum, 0, {
        end_col = #line,
        hl_group = "SuperMarkdownMermaidReady",
        priority = 100,
      })
    elseif line:find("▼") or line:find("▶") or line:find("◀") or line:find("──") then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_ID, lnum, 0, {
        end_col = #line,
        hl_group = "SuperMarkdownMermaidArrow",
        priority = 90,
      })
    elseif line:find("│") and not line:find("┌") and not line:find("└") and not line:find("╭") and not line:find("╰") then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_ID, lnum, 0, {
        end_col = #line,
        hl_group = "SuperMarkdownMermaidNodeLabel",
        priority = 90,
      })
    else
      pcall(vim.api.nvim_buf_set_extmark, buf, NS_ID, lnum, 0, {
        end_col = #line,
        hl_group = "SuperMarkdownTableBorder",
        priority = 80,
      })
    end
  end
end

function M.open(mermaid_code)
  M.close()

  local p_opts = config.options.mermaid.preview_win or {}
  local width = math.floor(vim.o.columns * (p_opts.width or 0.85))
  local height = math.floor(vim.o.lines * (p_opts.height or 0.85))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].swapfile = false

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
    footer = " [q/<Esc>] Close | [s] Side Preview Pane | [a] Toggle ASCII/Image | [o] Open External | [r] Recompile ",
    footer_pos = "center",
  })

  local mode = "ascii"
  local latest_result = nil

  local function bind_keys(buf)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
    local set_keymap = function(key, fn)
      vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
    end

    set_keymap("q", M.close)
    set_keymap("Q", M.close)
    set_keymap("<Esc>", M.close)

    set_keymap("s", function()
      M.close()
      require("super-markdown.preview_pane").open()
    end)

    set_keymap("a", function()
      if mode == "ascii" then
        mode = "image"
        if latest_result and latest_result.png then
          M._show_image(latest_result, width, height, bind_keys, function()
            mode = "ascii"
            M._show_ascii(latest_result, bind_keys)
          end)
        else
          vim.notify("SuperMarkdown: Compiling PNG image...", vim.log.levels.INFO)
          compiler.compile(mermaid_code, function(_, result)
            latest_result = result or latest_result
            if result and result.png then
              M._show_image(result, width, height, bind_keys, function()
                mode = "ascii"
                M._show_ascii(latest_result, bind_keys)
              end)
            else
              mode = "ascii"
              vim.notify("SuperMarkdown: PNG image compilation unavailable", vim.log.levels.WARN)
            end
          end)
        end
      else
        mode = "ascii"
        M._show_ascii(latest_result, bind_keys)
      end
    end)

    set_keymap("o", function()
      local open_target = function(res)
        local target = res and (res.png or res.svg)
        if target and vim.fn.filereadable(target) == 1 then
          vim.ui.open(target)
          vim.notify("Opened diagram in external viewer: " .. target, vim.log.levels.INFO)
        else
          vim.notify("No external image file available (offline or API unreachable)", vim.log.levels.WARN)
        end
      end

      if latest_result and (latest_result.png or latest_result.svg) then
        open_target(latest_result)
      else
        vim.notify("SuperMarkdown: Exporting Mermaid SVG/PNG...", vim.log.levels.INFO)
        compiler.compile(mermaid_code, function(_, result)
          latest_result = result or latest_result
          open_target(latest_result)
        end)
      end
    end)

    set_keymap("r", function()
      if latest_result then
        if latest_result.png then pcall(os.remove, latest_result.png) end
        if latest_result.svg then pcall(os.remove, latest_result.svg) end
      end
      M.open(mermaid_code)
    end)
  end

  -- Render pure-Lua ASCII diagram IMMEDIATELY (zero external calls unless user presses [o] or [a])
  local ascii_mod = require("super-markdown.mermaid.ascii")
  local immediate_ascii = ascii_mod.render(mermaid_code)
  latest_result = { ascii = immediate_ascii }
  M._show_ascii(latest_result, bind_keys)

  -- Only pre-compile external PNG if user explicitly configured backend == "kitty"
  if config.options.mermaid.backend == "kitty" and is_kitty_terminal() then
    compiler.compile(mermaid_code, function(_, result)
      if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
        return
      end
      latest_result = result or latest_result
      if result and result.png then
        mode = "image"
        M._show_image(result, width, height, bind_keys, function()
          mode = "ascii"
          M._show_ascii(latest_result, bind_keys)
        end)
      end
    end)
  end
end

function M._show_ascii(result, bind_keys)
  if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then return end
  if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) or vim.bo[preview_buf].buftype == "terminal" then
    preview_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[preview_buf].bufhidden = "wipe"
    vim.bo[preview_buf].buftype = "nofile"
    vim.bo[preview_buf].swapfile = false
    vim.api.nvim_win_set_buf(preview_win, preview_buf)
  end

  local lines = { "" }
  for _, l in ipairs(result.ascii or { "No ASCII representation available." }) do
    table.insert(lines, "  " .. l)
  end
  table.insert(lines, "")

  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].readonly = false
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].readonly = true

  style_ascii_buffer(preview_buf)
  bind_keys(preview_buf)
end

function M._show_image(result, width, height, bind_keys, fallback_fn)
  if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then return end
  if not (result and result.png and is_kitty_terminal() and vim.fn.executable("kitty") == 1) then
    if fallback_fn then fallback_fn() end
    return
  end

  -- Create a fresh unmodified buffer for jobstart({ term = true })
  local term_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[term_buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(preview_win, term_buf)
  preview_buf = term_buf
  bind_keys(term_buf)

  -- Pass explicit --place so kitty icat works inside Neovim's pty without pixel-size ioctl errors
  local place_arg = string.format("%dx%d@0x0", math.max(20, width - 4), math.max(10, height - 4))
  local cmd = {
    "kitty",
    "+kitten",
    "icat",
    "--transfer-mode=stream",
    "--place=" .. place_arg,
    "--align=center",
    result.png,
  }

  local ok = pcall(vim.fn.jobstart, cmd, {
    term = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.schedule(function()
          if fallback_fn then fallback_fn() end
        end)
      end
    end,
  })
  if not ok and fallback_fn then
    fallback_fn()
  end
end

return M
