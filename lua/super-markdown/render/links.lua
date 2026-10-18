local M = {}

function M.render(bufnr, ns_id, lnum, line, opts)
  if not opts.enabled then return end

  local icon = opts.icon or "󰌹 "
  local hl = opts.hl or "SuperMarkdownLink"

  local search_pos = 1
  while true do
    local s_start, s_end, link_text, link_url = line:find("%[([^%]]+)%]%(([^%)]+)%)", search_pos)
    if not s_start then break end

    -- Check if it's an image ![alt](url) -> if image, skip link styling or style differently
    local is_image = (s_start > 1 and line:sub(s_start - 1, s_start - 1) == "!")

    if not is_image then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s_start - 1, {
        end_col = s_start,
        conceal = "",
        virt_text = {
          { icon, hl },
        },
        virt_text_pos = "inline",
        priority = 90,
      })

      -- Conceal ](url)
      local url_start = s_start + #link_text + 1
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, url_start - 1, {
        end_col = s_end,
        conceal = "",
        priority = 90,
      })
    end

    search_pos = s_end + 1
  end
end

return M
