local M = {}

function M.render(bufnr, ns_id, lnum, line, in_codeblock, opts)
  if not opts or not opts.enabled then return in_codeblock end

  local border_hl = opts.border_hl or "SuperMarkdownCodeBorder"
  local lang_hl = "SuperMarkdownCodeLang"
  local block_hl = opts.hl or "SuperMarkdownCodeBlock"
  local border_char = opts.border_char or "│"
  local show_border = opts.border ~= false
  local min_width = opts.width or 60

  -- 1. Check for opening fence: e.g. ```lua or ~~~python
  local indent, lang = line:match("^(%s*)```+([%w_%-%+]*)(.*)$")
  local fence_type = "`"
  if not indent then
    indent, lang = line:match("^(%s*)~~~+([%w_%-%+]*)(.*)$")
    fence_type = "~"
  end

  if indent and not in_codeblock then
    local lang_clean = vim.trim(lang):lower()
    local display_badge = (opts.language_icons and opts.language_icons[lang_clean])
      or (lang_clean ~= "" and (" " .. lang_clean) or " code")

    if show_border then
      local badge_len = vim.fn.strdisplaywidth(display_badge) + 2
      local filler = string.rep("─", math.max(4, min_width - badge_len - #indent - 4))

      local top_decor = {
        { indent .. "╭─ ", border_hl },
        { display_badge, lang_hl },
        { " " .. filler .. "╮", border_hl },
      }

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
        virt_lines = { top_decor },
        virt_lines_above = true,
        priority = 90,
      })
    end

    -- Render opening fence line as part of the block
    local extmark_opts = {
      line_hl_group = block_hl,
      priority = 90,
    }
    if show_border then
      extmark_opts.virt_text = { { indent .. border_char .. " ", border_hl } }
      extmark_opts.virt_text_pos = "inline"
    end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, extmark_opts)

    return {
      lang = lang_clean,
      indent = indent,
      fence_type = fence_type,
    }
  end

  -- 2. Check for closing fence: e.g. ``` or ~~~
  local close_indent = nil
  if in_codeblock then
    if in_codeblock.fence_type == "~" then
      close_indent = line:match("^(%s*)~~~+%s*$")
    else
      close_indent = line:match("^(%s*)```+%s*$")
    end
  end

  if close_indent and in_codeblock then
    local extmark_opts = {
      line_hl_group = block_hl,
      priority = 90,
    }
    if show_border then
      extmark_opts.virt_text = { { close_indent .. border_char .. " ", border_hl } }
      extmark_opts.virt_text_pos = "inline"
    end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, extmark_opts)

    if show_border then
      local filler = string.rep("─", math.max(4, min_width - #close_indent - 2))
      local bot_decor = {
        { close_indent .. "╰" .. filler .. "╯", border_hl },
      }

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
        virt_lines = { bot_decor },
        virt_lines_above = false,
        priority = 90,
      })
    end

    return nil
  end

  -- 3. Interior lines inside the code block
  if in_codeblock then
    local pad = in_codeblock.indent or ""
    local extmark_opts = {
      line_hl_group = block_hl,
      priority = 90,
    }
    if show_border then
      extmark_opts.virt_text = { { pad .. border_char .. " ", border_hl } }
      extmark_opts.virt_text_pos = "inline"
    end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, extmark_opts)
    return in_codeblock
  end

  return in_codeblock
end

return M
