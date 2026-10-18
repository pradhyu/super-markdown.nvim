local config = require("super-markdown.config")

local M = {}

--- Calculate fold level for a markdown line
--- Headings define hierarchical folds:
--- # -> level 1 (>1)
--- ## -> level 2 (>2)
--- ### -> level 3 (>3)
--- Any text in between maintains the fold level (=)
--- @param lnum number 1-indexed line number
--- @return string fold expression result
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  local hashes = line:match("^%s*(#+)%s")
  if hashes then
    local level = #hashes
    if level >= 1 and level <= 6 then
      return ">" .. level
    end
  end
  return "="
end

--- Custom foldtext display showing heading icon, title, and line count
--- @return string
function M.foldtext()
  local start_lnum = vim.v.foldstart
  local end_lnum = vim.v.foldend
  local count = end_lnum - start_lnum + 1
  local start_line = vim.fn.getline(start_lnum)

  local hashes, title = start_line:match("^%s*(#+)%s*(.*)$")
  if hashes then
    local level = math.min(#hashes, 6)
    local icons = nil
    if config.options and config.options.render and config.options.render.headings then
      icons = config.options.render.headings.icons
    end
    local icon = (icons and icons[level]) or (string.rep("#", level) .. " ")
    return string.format(" %s%s  ⋯ (%d lines)", icon, title, count)
  end

  return string.format(" %s  ⋯ (%d lines)", vim.trim(start_line), count)
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

--- Fold all sections in the current window
function M.fold_all()
  vim.cmd("normal! zM")
  vim.notify("SuperMarkdown: Folded all sections 󰘖", vim.log.levels.INFO)
end

--- Unfold all sections in the current window
function M.unfold_all()
  vim.cmd("normal! zR")
  vim.notify("SuperMarkdown: Unfolded all sections 󰘕", vim.log.levels.INFO)
end

--- Toggle fold under cursor
function M.toggle_fold()
  vim.cmd("normal! za")
end

--- Set fold level in current window
--- @param level number Target fold level (e.g. 1 for H1 only, 2 for H1+H2)
function M.fold_level(level)
  level = tonumber(level) or 0
  pcall(vim.api.nvim_set_option_value, "foldlevel", level, { win = 0 })
  vim.notify(string.format("SuperMarkdown: Fold level set to %d", level), vim.log.levels.INFO)
end

return M
