local M = {}

local function get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return (ok and hl) or {}
end

local function to_hex(num)
  return type(num) == "number" and string.format("#%06x", num) or nil
end

local function get_fg(name, fallback)
  local hl = get_hl(name)
  return to_hex(hl.fg) or fallback
end

local function get_bg(name, fallback)
  local hl = get_hl(name)
  return to_hex(hl.bg) or fallback
end

function M.setup()
  local set_hl = function(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end

  local is_dark = vim.o.background ~= "light"

  -- Dynamically extract colors from the active theme
  local normal_fg = get_fg("Normal", is_dark and "#c0caf5" or "#374151")
  local normal_bg = get_bg("Normal", is_dark and "#1a1b26" or "#ffffff")
  local comment_fg = get_fg("Comment", is_dark and "#6e6f70" or "#9ca3af")
  local delimiter_fg = get_fg("Delimiter", comment_fg)
  local float_border = get_fg("FloatBorder", delimiter_fg)
  local cursorline_bg = get_bg("CursorLine", get_bg("Visual", is_dark and "#24283b" or "#e5e7eb"))

  -- Syntax accents from theme
  local fn_fg = get_fg("Function", get_fg("Title", "#7aa2f7"))
  local id_fg = get_fg("Identifier", "#7dcfff")
  local kw_fg = get_fg("Keyword", get_fg("Statement", "#bb9af7"))
  local type_fg = get_fg("Type", "#08bdba")
  local const_fg = get_fg("Constant", "#5ae0df")
  local spec_fg = get_fg("Special", fn_fg)
  local str_fg = get_fg("String", "#9ece6a")

  -- Headings: distinctly mapped to theme syntax tokens for clear visual hierarchy
  local h1_fg = fn_fg
  local h2_fg = id_fg
  local h3_fg = kw_fg
  local h4_fg = type_fg
  local h5_fg = const_fg
  local h6_fg = spec_fg

  -- Headings
  set_hl("SuperMarkdownH1", { fg = h1_fg, bold = true })
  set_hl("SuperMarkdownH2", { fg = h2_fg, bold = true })
  set_hl("SuperMarkdownH3", { fg = h3_fg, bold = true })
  set_hl("SuperMarkdownH4", { fg = h4_fg, bold = true })
  set_hl("SuperMarkdownH5", { fg = h5_fg, bold = true })
  set_hl("SuperMarkdownH6", { fg = h6_fg, bold = true })

  -- Heading Background Banners (soft background from theme cursorline)
  set_hl("SuperMarkdownH1Bg", { fg = h1_fg, bg = cursorline_bg, bold = true })
  set_hl("SuperMarkdownH2Bg", { fg = h2_fg, bg = cursorline_bg, bold = true })
  set_hl("SuperMarkdownH3Bg", { fg = h3_fg, bold = true })
  set_hl("SuperMarkdownH4Bg", { fg = h4_fg, bold = true })
  set_hl("SuperMarkdownH5Bg", { fg = h5_fg, bold = true })
  set_hl("SuperMarkdownH6Bg", { fg = h6_fg, bold = true })

  -- Checkboxes
  set_hl("SuperMarkdownCheckboxUnchecked", { fg = comment_fg })
  set_hl("SuperMarkdownCheckboxChecked", { fg = str_fg, bold = true })
  set_hl("SuperMarkdownCheckboxCanceled", { fg = comment_fg, strikethrough = true })
  set_hl("SuperMarkdownCheckboxProgress", { fg = const_fg })
  set_hl("SuperMarkdownCheckboxImportant", { fg = spec_fg, bold = true })
  set_hl("SuperMarkdownCheckboxQuestion", { fg = kw_fg })

  -- Callouts
  set_hl("SuperMarkdownCalloutNote", { fg = fn_fg, bold = true })
  set_hl("SuperMarkdownCalloutTip", { fg = str_fg, bold = true })
  set_hl("SuperMarkdownCalloutImportant", { fg = kw_fg, bold = true })
  set_hl("SuperMarkdownCalloutWarning", { fg = const_fg, bold = true })
  set_hl("SuperMarkdownCalloutCaution", { fg = spec_fg, bold = true })
  set_hl("SuperMarkdownCalloutDanger", { fg = spec_fg, bold = true })
  set_hl("SuperMarkdownCalloutTodo", { fg = type_fg, bold = true })
  set_hl("SuperMarkdownCalloutInfo", { fg = id_fg, bold = true })
  set_hl("SuperMarkdownCalloutQuestion", { fg = kw_fg, bold = true })
  set_hl("SuperMarkdownCalloutAbstract", { fg = id_fg, bold = true })

  -- Tables
  set_hl("SuperMarkdownTableBorder", { fg = float_border })
  set_hl("SuperMarkdownTableHeader", { fg = h1_fg, bold = true })

  -- Codeblocks
  set_hl("SuperMarkdownCodeBorder", { fg = float_border })
  set_hl("SuperMarkdownCodeBlock", { bg = normal_bg })
  set_hl("SuperMarkdownCodeLang", { fg = fn_fg, bold = true })

  -- Dividers
  set_hl("SuperMarkdownDivider", { fg = float_border })

  -- Links & Inline Text Styles
  set_hl("SuperMarkdownLink", { fg = id_fg, underline = true })
  set_hl("SuperMarkdownBold", { fg = normal_fg, bold = true })
  set_hl("SuperMarkdownItalic", { fg = kw_fg, italic = true })
  set_hl("SuperMarkdownInlineCode", { fg = const_fg, bg = cursorline_bg })

  -- List Items & Key-Value Contrast
  set_hl("SuperMarkdownListBullet", { fg = fn_fg })
  set_hl("SuperMarkdownListBulletSub", { fg = id_fg })
  set_hl("SuperMarkdownListNumber", { fg = fn_fg, bold = true })
  set_hl("SuperMarkdownListKey", { fg = id_fg, bold = true })
  set_hl("SuperMarkdownListColon", { fg = comment_fg })
  set_hl("SuperMarkdownIndentGuide", { fg = comment_fg })

  -- Blockquotes
  set_hl("SuperMarkdownQuote", { fg = comment_fg, italic = true })
  set_hl("SuperMarkdownQuoteBorder", { fg = float_border })

  -- Mermaid Indicators & Syntax Highlighting (Muted & Theme-Related)
  local box_fg = float_border
  local arrow_fg = spec_fg
  set_hl("SuperMarkdownMermaidBox", { fg = box_fg })
  set_hl("SuperMarkdownMermaidType", { fg = box_fg }) -- box borders in ascii diagrams
  set_hl("SuperMarkdownMermaidArrow", { fg = arrow_fg }) -- arrows ▶, ▼, -->
  set_hl("SuperMarkdownMermaidNodeLabel", { fg = normal_fg }) -- readable node text inside boxes
  set_hl("SuperMarkdownMermaidEdgeLabel", { fg = type_fg, italic = true }) -- edge labels [text]
  set_hl("SuperMarkdownMermaidNodeId", { fg = id_fg }) -- node identifiers
  set_hl("SuperMarkdownMermaidReady", { fg = comment_fg }) -- subtle [Live In-Buffer Render] badge
  set_hl("SuperMarkdownMermaidWait", { fg = const_fg, italic = true })
  set_hl("SuperMarkdownMermaidError", { fg = spec_fg })
  set_hl("SuperMarkdownMermaidKeyword", { fg = kw_fg, bold = true })
  set_hl("SuperMarkdownMermaidComment", { fg = comment_fg, italic = true })
  set_hl("SuperMarkdownMermaidString", { fg = str_fg })
  set_hl("SuperMarkdownMermaidNumber", { fg = const_fg })

  -- TOC Sidebar (Matching exact Markdown colors)
  set_hl("SuperMarkdownTocTitle", { fg = fn_fg, bold = true })
  set_hl("SuperMarkdownTocActive", { bg = cursorline_bg, bold = true })
  for i = 1, 6 do
    set_hl("SuperMarkdownTocH" .. i, { link = "SuperMarkdownH" .. i })
  end

  -- Spec & LLM Traceability Badges
  set_hl("SuperMarkdownSpecBadgeImpl", { fg = id_fg, bg = cursorline_bg, bold = true })
  set_hl("SuperMarkdownSpecBadgeTest", { fg = str_fg, bg = cursorline_bg, bold = true })
  set_hl("SuperMarkdownSpecReqId", { fg = const_fg, bold = true })

  -- Header Folder Icons
  set_hl("SuperMarkdownFolderOpen", { fg = const_fg, bold = true })
  set_hl("SuperMarkdownFolderClosed", { fg = fn_fg, bold = true })

  -- Focus Mode (Dimmed text outside active block)
  local has_diag = vim.fn.hlexists("DiagnosticUnnecessary") == 1
  set_hl("SuperMarkdownDimmed", {
    fg = comment_fg,
    link = has_diag and "DiagnosticUnnecessary" or nil,
    default = true,
  })
end

-- Auto-update highlights on colorscheme switch
local augroup = vim.api.nvim_create_augroup("SuperMarkdownHighlightsAuto", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup,
  callback = function()
    M.setup()
  end,
})

return M
