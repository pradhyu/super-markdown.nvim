local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local preview_win = nil
local preview_buf = nil

--- Convert heading text to a GitHub-style markdown anchor slug
--- @param title string
--- @return string
local function slugify(title)
  local s = vim.trim(title):lower()
  s = s:gsub("[^%w%s%-_]", "")
  s = s:gsub("%s+", "-")
  return s
end

--- Extract the link target or file reference under cursor
--- @param bufnr number
--- @param lnum number 1-indexed
--- @param col number 1-indexed
--- @return table|nil target_info { kind, raw, path, start_line, end_line, anchor }
function M.get_reference_at(bufnr, lnum, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  lnum = lnum or cursor[1]
  col = col or (cursor[2] + 1)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  -- 1. Check standard Markdown links [text](target)
  local search_pos = 1
  while true do
    local s_start, s_end, text, target = line:find("%[([^%]]+)%]%(([^%)]+)%)", search_pos)
    if not s_start then break end
    if col >= s_start and col <= s_end then
      local clean_target = vim.trim(target)
      if clean_target:match("^https?://") or clean_target:match("^mailto:") then
        return { kind = "url", raw = clean_target, label = text }
      elseif clean_target:match("^#") then
        return { kind = "anchor", raw = clean_target, anchor = clean_target:sub(2), label = text }
      else
        local resolved, s_line, e_line = analyzer.resolve_reference(clean_target, bufnr)
        return {
          kind = "file",
          raw = clean_target,
          path = resolved or clean_target,
          start_line = s_line,
          end_line = e_line,
          label = text,
        }
      end
    end
    search_pos = s_end + 1
  end

  -- 2. Check @impl: or @test: traceability tags on this line
  for _, role in ipairs({ "impl", "test" }) do
    local s_start, s_end, tag_target = line:find("@" .. role .. "%s*:%s*([^%s,`%)%]]+)")
    if s_start and tag_target then
      local resolved, s_line, e_line = analyzer.resolve_reference(tag_target, bufnr)
      return {
        kind = "file",
        role = role,
        raw = tag_target,
        path = resolved or tag_target,
        start_line = s_line,
        end_line = e_line,
      }
    end
  end

  -- 3. Check inline backtick code spans `path/to/file.lua:42`
  search_pos = 1
  while true do
    local s_start, s_end, code_span = line:find("`([^`]+)`", search_pos)
    if not s_start then break end
    if col >= s_start and col <= s_end then
      local cleaned = vim.trim(code_span):gsub("^@[%a]+%s*:%s*", "")
      local resolved, s_line, e_line = analyzer.resolve_reference(cleaned, bufnr)
      if resolved and vim.fn.filereadable(resolved) == 1 then
        return {
          kind = "file",
          raw = cleaned,
          path = resolved,
          start_line = s_line,
          end_line = e_line,
        }
      end
    end
    search_pos = s_end + 1
  end

  return nil
end

--- Jump to a heading anchor in the given buffer
--- @param bufnr number
--- @param anchor string
--- @return boolean
local function jump_to_anchor(bufnr, anchor)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local target_slug = anchor:lower():gsub("^#", "")
  for i, line in ipairs(lines) do
    local _, title = line:match("^(#+)%s+(.*)$")
    if title then
      if slugify(title) == target_slug or title:lower():find(target_slug, 1, true) then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        vim.cmd("normal! zvzz")
        return true
      end
    end
  end
  return false
end

--- Follow markdown link, anchor, or code traceability reference under cursor
function M.follow()
  local bufnr = vim.api.nvim_get_current_buf()
  local ref = M.get_reference_at(bufnr)
  if not ref then
    vim.notify("SuperMarkdown: No markdown link or file reference under cursor", vim.log.levels.WARN)
    return false
  end

  if ref.kind == "url" then
    vim.ui.open(ref.raw)
    vim.notify("SuperMarkdown: Opening web link: " .. ref.raw, vim.log.levels.INFO)
    return true
  end

  if ref.kind == "anchor" then
    if jump_to_anchor(bufnr, ref.anchor) then
      return true
    else
      vim.notify("SuperMarkdown: Heading anchor '#" .. ref.anchor .. "' not found", vim.log.levels.WARN)
      return false
    end
  end

  if ref.kind == "file" then
    local target_path = ref.path
    if vim.fn.filereadable(target_path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      if ref.start_line then
        pcall(vim.api.nvim_win_set_cursor, 0, { ref.start_line, 0 })
        vim.cmd("normal! zvzz")
      end
      return true
    else
      vim.ui.input({ prompt = "File '" .. target_path .. "' does not exist. Create? (y/n): " }, function(input)
        if input and input:lower() == "y" then
          local p_dir = vim.fs.dirname(target_path)
          if p_dir and vim.fn.isdirectory(p_dir) == 0 then
            vim.fn.mkdir(p_dir, "p")
          end
          vim.cmd("edit " .. vim.fn.fnameescape(target_path))
        end
      end)
      return false
    end
  end

  return false
end

--- Close floating reference preview window if open
function M.close_preview()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    pcall(vim.api.nvim_win_close, preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

--- Peek at the file or section referenced under cursor in a floating window
function M.preview()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    M.close_preview()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local ref = M.get_reference_at(bufnr)
  if not ref or ref.kind ~= "file" then
    vim.notify("SuperMarkdown: Place cursor on a local file link or `@impl:`/`@test:` tag to preview", vim.log.levels.INFO)
    return nil
  end

  if vim.fn.filereadable(ref.path) == 0 then
    vim.notify("SuperMarkdown: Referenced file '" .. ref.raw .. "' does not exist yet", vim.log.levels.WARN)
    return nil
  end

  local file_lines = vim.fn.readfile(ref.path)
  local s_line = ref.start_line or 1
  local e_line = ref.end_line or math.min(#file_lines, s_line + 40)
  s_line = math.max(1, math.min(#file_lines, s_line))
  e_line = math.max(s_line, math.min(#file_lines, e_line))

  local slice = {}
  for i = s_line, e_line do
    table.insert(slice, file_lines[i])
  end

  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, slice)
  local ft = vim.filetype.match({ filename = ref.path }) or "text"
  vim.bo[preview_buf].filetype = ft
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "wipe"

  local width = math.min(88, math.floor(vim.o.columns * 0.8))
  local height = math.min(math.max(6, #slice + 2), 26)

  preview_win = vim.api.nvim_open_win(preview_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = string.format(" 󰅩 %s (L%d-%d) ", vim.fn.fnamemodify(ref.path, ":."), s_line, e_line),
    title_pos = "center",
  })

  vim.keymap.set("n", "q", M.close_preview, { buffer = preview_buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", M.close_preview, { buffer = preview_buf, nowait = true, silent = true })
  vim.keymap.set("n", "<CR>", function()
    M.close_preview()
    vim.cmd("edit " .. vim.fn.fnameescape(ref.path))
    if ref.start_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { ref.start_line, 0 })
      vim.cmd("normal! zvzz")
    end
  end, { buffer = preview_buf, nowait = true, silent = true })

  return { win = preview_win, buf = preview_buf, ref = ref }
end

return M
