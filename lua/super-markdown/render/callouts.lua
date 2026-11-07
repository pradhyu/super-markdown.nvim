local M = {}

function M.render(bufnr, ns_id, lnum, line, prev_callout, opts)
  if not opts.enabled then return nil end

  -- Check for callout start: ^(%s*>%s*)%[!([%w_%-]+)%]%s*(.*)$
  local prefix, callout_type, title = line:match("^(%s*>%s*)%[!([%w_%-]+)%]%s*(.*)$")
  if prefix and callout_type then
    local upper_type = callout_type:upper()
    local c_info = opts.types[upper_type] or {
      icon = "󰋽 ",
      title = upper_type:sub(1, 1) .. upper_type:sub(2):lower(),
      hl = "SuperMarkdownCalloutNote",
    }

    local display_title = (title and #title > 0) and title or c_info.title
    local start_col = 0
    local end_col = #line
    local icon_str = c_info.icon or "󰋽 "
    if not icon_str:match("%s$") then
      icon_str = icon_str .. " "
    end

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, start_col, {
      end_col = end_col,
      conceal = "",
      virt_text = {
        { opts.border_char .. " ", c_info.hl },
        { icon_str, c_info.hl },
        { display_title, c_info.hl },
      },
      virt_text_pos = "inline",
      priority = 100,
    })

    return { type = upper_type, hl = c_info.hl }
  end

  -- Check if line is continuing a quote/callout: ^(%s*>%s*)(.*)$
  local q_prefix, _ = line:match("^(%s*>%s*)(.*)$")
  if q_prefix then
    local quote_hl = (prev_callout and prev_callout.hl) or "SuperMarkdownTableBorder"
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
      end_col = #q_prefix,
      conceal = "",
      virt_text = {
        { opts.border_char .. " ", quote_hl },
      },
      virt_text_pos = "inline",
      priority = 90,
    })
    return prev_callout or { type = "QUOTE", hl = quote_hl }
  end

  return nil
end

return M
