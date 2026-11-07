local M = {}

--- Renders inline backtick code snippets with concealed backticks and soft pill background
function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts or opts.enabled == false then return end

  -- Skip code block fences
  if line:match("^%s*```") or line:match("^%s*~~~") then return end

  local len = #line
  local i = 1
  local hl = opts.hl or "SuperMarkdownInlineCode"

  while i <= len do
    local ch = line:sub(i, i)
    if ch == "\\" then
      i = i + 2
    elseif ch == "`" then
      -- Count opening backticks
      local ticks = 1
      while i + ticks <= len and line:sub(i + ticks, i + ticks) == "`" do
        ticks = ticks + 1
      end

      -- If it's 3 or more backticks, skip (it's a code block delimiter)
      if ticks >= 3 then
        i = i + ticks
      else
        local tick_pattern = string.rep("`", ticks)
        local span_start = i - 1 -- 0-based col
        local content_start = i + ticks - 1

        -- Search for matching closing backticks
        local close_start, close_end = line:find(tick_pattern, i + ticks, true)
        if close_start then
          local content_end = close_start - 1
          local span_end = close_end

          -- 1. Conceal opening backtick(s)
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, span_start, {
            end_col = content_start,
            conceal = "",
            priority = 90,
          })

          -- 2. Highlight code text with pill background
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, content_start, {
            end_col = content_end,
            hl_group = hl,
            priority = 92,
          })

          -- 3. Conceal closing backtick(s)
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, content_end, {
            end_col = span_end,
            conceal = "",
            priority = 90,
          })

          i = close_end + 1
        else
          i = i + ticks
        end
      end
    else
      i = i + 1
    end
  end
end

return M
