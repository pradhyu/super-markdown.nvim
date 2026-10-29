local M = {}

function M.render(bufnr, ns_id, lnum, line, opts, sec_info)
  if not opts or not opts.enabled then return end

  -- Match heading: ^(#+)%s+(.*)$
  local hashes, _ = line:match("^(#+)%s+(.*)$")
  if not hashes or #hashes > 6 then return end

  local level = #hashes
  local icon = opts.icons[level] or "󰲡 "
  local fg_hl = opts.foregrounds[level] or "SuperMarkdownH1"
  local bg_hl = opts.backgrounds[level] or "SuperMarkdownH1Bg"

  local virt_chunks = {}
  if opts.folder_icon ~= false then
    local open_icon = opts.open_folder_icon or "󰝰 "
    table.insert(virt_chunks, { open_icon, "SuperMarkdownFolderOpen" })
  end
  table.insert(virt_chunks, { icon, fg_hl })

  -- Replace the leading hashes and space with folder icon + heading level icon
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
    end_col = #hashes + 1,
    conceal = "",
    virt_text = virt_chunks,
    virt_text_pos = "inline",
    line_hl_group = level <= 2 and bg_hl or nil,
    priority = 100,
  })

  -- Render Spec Progress & Traceability Badges at end of heading line
  if opts.spec_badges ~= false and sec_info and sec_info.counts then
    local c = sec_info.counts
    local badges = {}

    if c.total_tasks and c.total_tasks > 0 then
      local done = c.checked or 0
      local hl = (done == c.total_tasks) and "SuperMarkdownCheckboxChecked" or "SuperMarkdownCheckboxProgress"
      table.insert(badges, { string.format("  󰄵 %d/%d", done, c.total_tasks), hl })
    end

    if c.important and c.important > 0 then
      table.insert(badges, { string.format("  󰀦 %d", c.important), "SuperMarkdownCheckboxImportant" })
    end

    if c.question and c.question > 0 then
      table.insert(badges, { string.format("  󰋽 %d", c.question), "SuperMarkdownCheckboxQuestion" })
    end

    if sec_info.refs and #sec_info.refs > 0 then
      local has_impl, has_test = false, false
      for _, r in ipairs(sec_info.refs) do
        if r.role == "impl" then has_impl = true end
        if r.role == "test" then has_test = true end
      end
      if has_impl then
        table.insert(badges, { "  󰅩 impl", "SuperMarkdownSpecBadgeImpl" })
      end
      if has_test then
        table.insert(badges, { "  󰙨 test", "SuperMarkdownSpecBadgeTest" })
      end
    end

    if #badges > 0 then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
        virt_text = badges,
        virt_text_pos = "eol",
        priority = 95,
      })
    end
  end
end

return M
