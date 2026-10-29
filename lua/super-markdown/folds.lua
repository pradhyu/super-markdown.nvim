local config = require("super-markdown.config")

local M = {}

--- Check if a 1-indexed line number is inside a fenced code block (``` or ~~~)
--- @param lnum number
--- @return boolean
local function is_in_codeblock(lnum)
  local in_block = false
  for i = 1, lnum - 1 do
    local l = vim.fn.getline(i)
    if l:match("^%s*```") or l:match("^%s*~~~") then
      in_block = not in_block
    end
  end
  return in_block
end

--- Calculate fold level for a markdown line.
--- In "toc" mode (default), every heading (# through ######) starts a level-1 fold (>1)
--- so that folding all sections (zM) keeps every heading visible as an interactive Table of Contents,
--- folding only the body text beneath each heading.
--- In "tree" mode, headings define nested folds (>1, >2, >3...).
--- @param lnum number 1-indexed line number
--- @return string fold expression result
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  local hashes = line:match("^%s*(#+)%s")
  if hashes then
    local level = #hashes
    if level >= 1 and level <= 6 and not is_in_codeblock(lnum) then
      local mode = (config.options and config.options.folds and config.options.folds.mode) or "toc"
      if mode == "tree" then
        return ">" .. level
      end
      return ">1"
    end
  end
  return "="
end

--- Custom foldtext display showing indentation, closed folder icon, heading icon, title, spec task rollup, and line count
--- @return string
function M.foldtext()
  local start_lnum = vim.v.foldstart
  local end_lnum = vim.v.foldend
  local count = end_lnum - start_lnum + 1
  local start_line = vim.fn.getline(start_lnum)

  -- Scan folded lines for task completion, blockers, and questions
  local checked, total_tasks, blockers, questions = 0, 0, 0, 0
  for l = start_lnum, end_lnum do
    local line = vim.fn.getline(l)
    local cb = line:match("^%s*[%-%*%+]%s+%[(.)%]") or line:match("^%s*%d+%.%s+%[(.)%]")
    if cb then
      if cb == "x" or cb == "X" then
        checked = checked + 1
        total_tasks = total_tasks + 1
      elseif cb == " " or cb == "/" then
        total_tasks = total_tasks + 1
      elseif cb == "!" then
        blockers = blockers + 1
        total_tasks = total_tasks + 1
      elseif cb == "?" then
        questions = questions + 1
      end
    end
  end

  local spec_parts = {}
  if total_tasks > 0 then
    table.insert(spec_parts, string.format("󰄵 %d/%d", checked, total_tasks))
  end
  if blockers > 0 then
    table.insert(spec_parts, string.format("󰀦 %d", blockers))
  end
  if questions > 0 then
    table.insert(spec_parts, string.format("󰋽 %d", questions))
  end
  local spec_str = #spec_parts > 0 and ("  [" .. table.concat(spec_parts, " · ") .. "]") or ""

  local hashes, title = start_line:match("^%s*(#+)%s*(.*)$")
  if hashes then
    local level = math.min(#hashes, 6)
    local h_opts = (config.options and config.options.render and config.options.render.headings) or {}
    local icons = h_opts.icons
    local icon = (icons and icons[level]) or (string.rep("#", level) .. " ")
    local folder = (h_opts.folder_icon ~= false) and (h_opts.closed_folder_icon or "󰉋 ") or ""
    local indent = string.rep("  ", level - 1)
    return string.format(" %s%s%s%s%s  ⋯ (%d lines)", indent, folder, icon, title, spec_str, count)
  end

  return string.format(" %s%s  ⋯ (%d lines)", vim.trim(start_line), spec_str, count)
end

--- Apply fold settings to a specific window
--- @param win number Window ID
--- @param bufnr number Buffer number
function M.attach_win(win, bufnr)
  if not win or win == -1 or not vim.api.nvim_win_is_valid(win) then return end
  local opts = (config.options and config.options.folds) or {}
  if opts.enabled == false then return end

  pcall(vim.api.nvim_set_option_value, "foldmethod", "expr", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldexpr", "v:lua.require'super-markdown.folds'.foldexpr(v:lnum)", { win = win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", tostring(opts.foldcolumn or "1"), { win = win })
  pcall(vim.api.nvim_set_option_value, "foldlevel", opts.foldlevel or 99, { win = win })

  if opts.foldtext ~= false then
    pcall(vim.api.nvim_set_option_value, "foldtext", "v:lua.require'super-markdown.folds'.foldtext()", { win = win })
  end

  -- Merge fillchars for foldopen, foldclose, foldsep (+ and - gutter icons)
  local current = ""
  pcall(function()
    current = vim.wo[win].fillchars or ""
  end)

  local parts = {}
  for _, item in ipairs(vim.split(current, ",")) do
    local k = vim.split(item, ":")[1]
    if k ~= "" and k ~= "foldopen" and k ~= "foldclose" and k ~= "foldsep" then
      table.insert(parts, item)
    end
  end

  table.insert(parts, "foldopen:" .. (opts.foldopen or "-"))
  table.insert(parts, "foldclose:" .. (opts.foldclose or "+"))
  table.insert(parts, "foldsep:" .. (opts.foldsep or "│"))

  pcall(vim.api.nvim_set_option_value, "fillchars", table.concat(parts, ","), { win = win })
end

--- Attach fold management to a buffer and its current/future windows
--- @param bufnr number Buffer number
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    M.attach_win(win, bufnr)
  end

  local group = vim.api.nvim_create_augroup("SuperMarkdownFolds_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = bufnr,
    callback = function(args)
      local win = vim.fn.bufwinid(args.buf)
      if win and win ~= -1 then
        M.attach_win(win, args.buf)
      end
    end,
  })
end

--- Fold all sections in the current window so only TOC headers are visible
function M.fold_all()
  vim.cmd("normal! zM")
  vim.notify("SuperMarkdown: Folded to TOC headers (press <CR> or za on any header to unfold) 󰉋", vim.log.levels.INFO)
end

--- Alias for folding buffer to TOC-only header outline
M.fold_toc = M.fold_all

--- Unfold all sections in the current window
function M.unfold_all()
  vim.cmd("normal! zR")
  vim.notify("SuperMarkdown: Unfolded all sections 󰝰", vim.log.levels.INFO)
end

--- Toggle fold under cursor
function M.toggle_fold()
  vim.cmd("normal! za")
end

--- Handle <CR> in Normal mode: if on a folded line or a Markdown heading, toggle fold!
--- @return boolean handled
function M.handle_normal_enter()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if vim.fn.foldclosed(lnum) ~= -1 then
    vim.cmd("normal! zo")
    return true
  end
  local line = vim.fn.getline(lnum)
  if line:match("^%s*#+%s") and not is_in_codeblock(lnum) then
    vim.cmd("normal! za")
    return true
  end
  return false
end

--- Set fold level in current window
--- @param level number Target fold level (e.g. 1 for H1 only, 2 for H1+H2)
function M.fold_level(level)
  level = tonumber(level) or 0
  pcall(vim.api.nvim_set_option_value, "foldlevel", level, { win = 0 })
  vim.notify(string.format("SuperMarkdown: Fold level set to %d", level), vim.log.levels.INFO)
end

return M
