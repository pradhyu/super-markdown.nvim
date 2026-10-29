local M = {}

function M.setup()
  local set_hl = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Headings
  set_hl("SuperMarkdownH1", { fg = "#7aa2f7", bold = true })
  set_hl("SuperMarkdownH2", { fg = "#7dcfff", bold = true })
  set_hl("SuperMarkdownH3", { fg = "#bb9af7", bold = true })
  set_hl("SuperMarkdownH4", { fg = "#9ece6a", bold = true })
  set_hl("SuperMarkdownH5", { fg = "#e0af68", bold = true })
  set_hl("SuperMarkdownH6", { fg = "#f7768e", bold = true })

  set_hl("SuperMarkdownH1Bg", { fg = "#7aa2f7", bg = "#1f2335", bold = true })
  set_hl("SuperMarkdownH2Bg", { fg = "#7dcfff", bg = "#1b2838", bold = true })
  set_hl("SuperMarkdownH3Bg", { fg = "#bb9af7", bg = "#252136", bold = true })
  set_hl("SuperMarkdownH4Bg", { fg = "#9ece6a", bg = "#1e2a22", bold = true })
  set_hl("SuperMarkdownH5Bg", { fg = "#e0af68", bg = "#2d261e", bold = true })
  set_hl("SuperMarkdownH6Bg", { fg = "#f7768e", bg = "#2d1f24", bold = true })

  -- Checkboxes
  set_hl("SuperMarkdownCheckboxUnchecked", { fg = "#787c99" })
  set_hl("SuperMarkdownCheckboxChecked", { fg = "#9ece6a", bold = true })
  set_hl("SuperMarkdownCheckboxCanceled", { fg = "#565f89", strikethrough = true })
  set_hl("SuperMarkdownCheckboxProgress", { fg = "#e0af68" })
  set_hl("SuperMarkdownCheckboxImportant", { fg = "#f7768e", bold = true })
  set_hl("SuperMarkdownCheckboxQuestion", { fg = "#bb9af7" })

  -- Callouts
  set_hl("SuperMarkdownCalloutNote", { fg = "#7aa2f7", bold = true })
  set_hl("SuperMarkdownCalloutTip", { fg = "#9ece6a", bold = true })
  set_hl("SuperMarkdownCalloutImportant", { fg = "#bb9af7", bold = true })
  set_hl("SuperMarkdownCalloutWarning", { fg = "#e0af68", bold = true })
  set_hl("SuperMarkdownCalloutCaution", { fg = "#f7768e", bold = true })
  set_hl("SuperMarkdownCalloutDanger", { fg = "#db4b4b", bold = true })
  set_hl("SuperMarkdownCalloutTodo", { fg = "#1abc9c", bold = true })
  set_hl("SuperMarkdownCalloutInfo", { fg = "#0db9d7", bold = true })
  set_hl("SuperMarkdownCalloutQuestion", { fg = "#b48ead", bold = true })
  set_hl("SuperMarkdownCalloutAbstract", { fg = "#7dcfff", bold = true })

  -- Tables
  set_hl("SuperMarkdownTableBorder", { fg = "#565f89" })
  set_hl("SuperMarkdownTableHeader", { fg = "#7aa2f7", bold = true })

  -- Codeblocks
  set_hl("SuperMarkdownCodeBorder", { fg = "#3b4261" })
  set_hl("SuperMarkdownCodeBlock", { bg = "#1a1b26" })
  set_hl("SuperMarkdownCodeLang", { fg = "#7aa2f7", bold = true })

  -- Dividers
  set_hl("SuperMarkdownDivider", { fg = "#414868" })

  -- Links
  set_hl("SuperMarkdownLink", { fg = "#7dcfff", underline = true })

  -- Mermaid Indicators & Syntax Highlighting
  set_hl("SuperMarkdownMermaidReady", { fg = "#9ece6a", bold = true })
  set_hl("SuperMarkdownMermaidWait", { fg = "#e0af68", italic = true })
  set_hl("SuperMarkdownMermaidError", { fg = "#f7768e" })
  set_hl("SuperMarkdownMermaidKeyword", { fg = "#bb9af7", bold = true })
  set_hl("SuperMarkdownMermaidType", { fg = "#7dcfff", bold = true })
  set_hl("SuperMarkdownMermaidArrow", { fg = "#f7768e", bold = true })
  set_hl("SuperMarkdownMermaidNodeId", { fg = "#e0af68", bold = true })
  set_hl("SuperMarkdownMermaidNodeLabel", { fg = "#9ece6a" })
  set_hl("SuperMarkdownMermaidEdgeLabel", { fg = "#7aa2f7" })
  set_hl("SuperMarkdownMermaidComment", { fg = "#565f89", italic = true })
  set_hl("SuperMarkdownMermaidString", { fg = "#9ece6a" })
  set_hl("SuperMarkdownMermaidNumber", { fg = "#ff9e64" })

  -- TOC Sidebar
  set_hl("SuperMarkdownTocTitle", { fg = "#bb9af7", bold = true })
  set_hl("SuperMarkdownTocActive", { fg = "#7aa2f7", bg = "#24283b", bold = true })

  -- Spec & LLM Traceability Badges
  set_hl("SuperMarkdownSpecBadgeImpl", { fg = "#7dcfff", bg = "#1b2838", bold = true })
  set_hl("SuperMarkdownSpecBadgeTest", { fg = "#9ece6a", bg = "#1e2a22", bold = true })
  set_hl("SuperMarkdownSpecReqId", { fg = "#ff9e64", bold = true })

  -- Header Folder Icons
  set_hl("SuperMarkdownFolderOpen", { fg = "#e0af68", bold = true })
  set_hl("SuperMarkdownFolderClosed", { fg = "#7aa2f7", bold = true })
end

return M
