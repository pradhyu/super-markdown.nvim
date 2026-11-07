local M = {}

local BULLET_ICONS = { "● ", "○ ", "▪ ", "▫ " }

--- Renders list hierarchy, bullets, ordered list numbering, indent guides, and key-value bold markers
function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts or opts.enabled == false then return false end

  -- 1. Check if line is an unordered list item: ^(%s*)([%-%*%+])(%s+)(.*)$
  local u_indent, u_bullet, u_space, u_rest = line:match("^(%s*)([%-%*%+])(%s+)(.*)$")
  if u_indent and u_bullet and u_space then
    -- Check if it's a checkbox task (let checkboxes.lua handle task checkboxes)
    if u_rest:match("^%[[%s%w%-%/%!%?]%]") then
      return false
    end

    local depth = math.floor(#u_indent / 2)
    local bullet_idx = (depth % #BULLET_ICONS) + 1
    local bullet_char = (opts.bullets and opts.bullets[bullet_idx]) or BULLET_ICONS[bullet_idx]
    local bullet_hl = (depth == 0) and "SuperMarkdownListBullet" or "SuperMarkdownListBulletSub"

    -- Render indent guides for nested items
    if #u_indent >= 2 and opts.indent_guides ~= false then
      for i = 0, #u_indent - 2, 2 do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, i, {
          end_col = i + 1,
          conceal = "",
          virt_text = { { "│", "SuperMarkdownIndentGuide" } },
          virt_text_pos = "inline",
          priority = 90,
        })
      end
    end

    -- Conceal raw bullet marker (- / * / +) and replace with clean bullet icon
    local b_start = #u_indent
    local b_end = b_start + #u_bullet + #u_space
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, b_start, {
      end_col = b_end,
      conceal = "",
      virt_text = { { bullet_char, bullet_hl } },
      virt_text_pos = "inline",
      priority = 95,
    })

    -- Check for Key-Value bullet pattern: - **Key**: Value or - **Key** - Value
    if opts.key_contrast ~= false and u_rest then
      M.render_key_value(bufnr, ns_id, lnum, b_end, u_rest)
    end
    return true
  end

  -- 2. Check if line is an ordered list item: ^(%s*)(%d+%.)(%s+)(.*)$
  local o_indent, o_num, o_space, o_rest = line:match("^(%s*)(%d+%.)(%s+)(.*)$")
  if o_indent and o_num and o_space then
    -- Render indent guides for nested items
    if #o_indent >= 2 and opts.indent_guides ~= false then
      for i = 0, #o_indent - 2, 2 do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, i, {
          end_col = i + 1,
          conceal = "",
          virt_text = { { "│", "SuperMarkdownIndentGuide" } },
          virt_text_pos = "inline",
          priority = 90,
        })
      end
    end

    local num_start = #o_indent
    local num_end = num_start + #o_num
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, num_start, {
      end_col = num_end,
      hl_group = "SuperMarkdownListNumber",
      priority = 95,
    })

    -- Check for Key-Value pattern: 1. **Key**: Value
    if opts.key_contrast ~= false and o_rest then
      local rest_start = num_end + #o_space
      M.render_key_value(bufnr, ns_id, lnum, rest_start, o_rest)
    end
    return true
  end

  return false
end

--- Highlight **Key**: or **Key** - patterns with clean contrast and concealed asterisks
function M.render_key_value(bufnr, ns_id, lnum, offset, text)
  -- Pattern: ^%*%*([^*]+)%*%*(%s*[:%-]%s*)
  local key, sep = text:match("^%*%*([^*]+)%*%*(%s*[:%-]%s*)")
  if key and sep then
    local open_ast_start = offset
    local open_ast_end = offset + 2
    local key_start = open_ast_end
    local key_end = key_start + #key
    local close_ast_start = key_end
    local close_ast_end = close_ast_start + 2
    local sep_start = close_ast_end
    local sep_end = sep_start + #sep

    -- Conceal opening **
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, open_ast_start, {
      end_col = open_ast_end,
      conceal = "",
      priority = 98,
    })

    -- Highlight key text
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, key_start, {
      end_col = key_end,
      hl_group = "SuperMarkdownListKey",
      priority = 98,
    })

    -- Conceal closing **
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, close_ast_start, {
      end_col = close_ast_end,
      conceal = "",
      priority = 98,
    })

    -- Subtle highlight for separator (: or -)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, sep_start, {
      end_col = sep_end,
      hl_group = "SuperMarkdownListColon",
      priority = 95,
    })
  end
end

return M
