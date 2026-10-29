local analyzer = require("super-markdown.spec.analyzer")

local M = {}

local STATUS_HL = {
  APPROVED = { icon = "󰄵 ", hl = "SuperMarkdownCheckboxChecked" },
  IMPLEMENTED = { icon = "󰄵 ", hl = "SuperMarkdownCheckboxChecked" },
  VERIFIED = { icon = "󰄵 ", hl = "SuperMarkdownCheckboxChecked" },
  DRAFT = { icon = "󰏫 ", hl = "SuperMarkdownCheckboxProgress" },
  REVIEW = { icon = "󰋽 ", hl = "SuperMarkdownCheckboxQuestion" },
  IN_PROGRESS = { icon = "󰄰 ", hl = "SuperMarkdownCheckboxProgress" },
  DEPRECATED = { icon = "󰀦 ", hl = "SuperMarkdownCheckboxImportant" },
}

function M.render(bufnr, ns_id, lnum, line, opts)
  if opts and opts.enabled == false then return end

  -- 1. Document Status metadata line: e.g. `> **Document Status**: APPROVED` or `status: DRAFT`
  local _, _, st_val = line:find("^>%s*%*%*[^%*]*[sS]tatus[^%*]*%*%*%s*:%s*`?([%w_%-]+)`?")
  if not st_val then
    _, _, st_val = line:find("^%s*status%s*:%s*([%w_%-]+)%s*$")
  end
  if st_val then
    local st_upper = st_val:upper()
    local meta = STATUS_HL[st_upper] or { icon = "󰍔 ", hl = "SuperMarkdownH2" }
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
      virt_text = {
        { string.format("  %s%s  (press <leader>msd to cycle)", meta.icon, st_upper), meta.hl },
      },
      virt_text_pos = "eol",
      priority = 95,
    })
  end

  -- 2. @impl: and @test: traceability tags
  for _, role in ipairs({ "impl", "test" }) do
    local s, e, target = line:find("@" .. role .. "%s*:%s*([^%s,`%)%]]+)")
    if s and target then
      local resolved = analyzer.resolve_reference(target, bufnr)
      local exists = resolved and vim.fn.filereadable(resolved) == 1
      local hl = role == "test" and "SuperMarkdownSpecBadgeTest" or "SuperMarkdownSpecBadgeImpl"
      local status_text = exists and " 󰄵 linked" or " 󰀦 missing"
      local status_hl = exists and "SuperMarkdownCheckboxChecked" or "SuperMarkdownCalloutWarning"

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        hl_group = hl,
        priority = 105,
      })
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, 0, {
        virt_text = {
          { status_text, status_hl },
        },
        virt_text_pos = "eol",
        priority = 92,
      })
    end
  end

  -- 3. Highlight Requirement IDs (REQ-01, FR-02, NFR-01, SEC-01, TC-01)
  local search_pos = 1
  while true do
    local s, e, req_id = line:find("([A-Z][A-Z0-9]?[A-Z0-9]?%-%d+)", search_pos)
    if not s then break end
    local prefix = req_id:match("^([A-Z]+)%-")
    if prefix == "REQ" or prefix == "FR" or prefix == "NFR" or prefix == "SEC" or prefix == "TC" or prefix == "UC" then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, s - 1, {
        end_col = e,
        hl_group = "SuperMarkdownSpecReqId",
        priority = 105,
      })
    end
    search_pos = e + 1
  end
end

return M
