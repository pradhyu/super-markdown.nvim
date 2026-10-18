local M = {}

M.defaults = {
  enabled = true,
  filetypes = { "markdown", "md", "markdown.mdx" },
  debounce_ms = 70,

  -- In-buffer rendering options
  render = {
    enabled = true,
    conceallevel = 2,
    concealcursor = "c", -- "c" keeps current line visible while editing in normal & insert mode
    headings = {
      enabled = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      signs = { "◉", "○", "✸", "◇", "▪", "▫" },
      backgrounds = {
        "SuperMarkdownH1Bg",
        "SuperMarkdownH2Bg",
        "SuperMarkdownH3Bg",
        "SuperMarkdownH4Bg",
        "SuperMarkdownH5Bg",
        "SuperMarkdownH6Bg",
      },
      foregrounds = {
        "SuperMarkdownH1",
        "SuperMarkdownH2",
        "SuperMarkdownH3",
        "SuperMarkdownH4",
        "SuperMarkdownH5",
        "SuperMarkdownH6",
      },
    },
    checkboxes = {
      enabled = true,
      icons = {
        unchecked = { icon = "󰄱 ", hl = "SuperMarkdownCheckboxUnchecked" },
        checked = { icon = "󰄵 ", hl = "SuperMarkdownCheckboxChecked" },
        canceled = { icon = "󰡖 ", hl = "SuperMarkdownCheckboxCanceled" },
        progress = { icon = "󰄰 ", hl = "SuperMarkdownCheckboxProgress" },
        important = { icon = "󰀦 ", hl = "SuperMarkdownCheckboxImportant" },
        question = { icon = "󰋽 ", hl = "SuperMarkdownCheckboxQuestion" },
      },
    },
    callouts = {
      enabled = true,
      border_char = "▍",
      types = {
        NOTE = { icon = "󰋽 ", title = "Note", hl = "SuperMarkdownCalloutNote" },
        TIP = { icon = "󰌶 ", title = "Tip", hl = "SuperMarkdownCalloutTip" },
        IMPORTANT = { icon = "󰅒 ", title = "Important", hl = "SuperMarkdownCalloutImportant" },
        WARNING = { icon = "󰀦 ", title = "Warning", hl = "SuperMarkdownCalloutWarning" },
        CAUTION = { icon = "󰳦 ", title = "Caution", hl = "SuperMarkdownCalloutCaution" },
        DANGER = { icon = "󰳦 ", title = "Danger", hl = "SuperMarkdownCalloutDanger" },
        TODO = { icon = "󰄱 ", title = "Todo", hl = "SuperMarkdownCalloutTodo" },
        INFO = { icon = "󰋽 ", title = "Info", hl = "SuperMarkdownCalloutInfo" },
        QUESTION = { icon = "󰋽 ", title = "Question", hl = "SuperMarkdownCalloutQuestion" },
        ABSTRACT = { icon = "󰨸 ", title = "Abstract", hl = "SuperMarkdownCalloutAbstract" },
      },
    },
    tables = {
      enabled = true,
      auto_align = true,
      box_drawing = true,
      head_sep = "─",
      vertical = "│",
      corners = {
        top_left = "┌",
        top_mid = "┬",
        top_right = "┐",
        mid_left = "├",
        mid_mid = "┼",
        mid_right = "┤",
        bot_left = "└",
        bot_mid = "┴",
        bot_right = "┘",
      },
      hl = "SuperMarkdownTableBorder",
      header_hl = "SuperMarkdownTableHeader",
    },
    codeblocks = {
      enabled = true,
      border = true,
      border_char = "│",
      width = 60,
      show_language = true,
      language_icons = {
        lua = "󰢱 lua",
        python = "󰌠 python",
        javascript = "󰌞 javascript",
        typescript = "󰛦 typescript",
        html = "󰌝 html",
        css = "󰌜 css",
        rust = "󰛦 rust",
        c = " c",
        cpp = " c++",
        go = "󰟓 go",
        bash = "󱆃 bash",
        sh = "󱆃 sh",
        zsh = "󱆃 zsh",
        json = " json",
        yaml = "󰡎 yaml",
        toml = "󰡎 toml",
        sql = "󰆼 sql",
        mermaid = "󰡷 mermaid",
        markdown = "󰍔 markdown",
      },
      hl = "SuperMarkdownCodeBlock",
      border_hl = "SuperMarkdownCodeBorder",
    },
    dividers = {
      enabled = true,
      char = "─",
      hl = "SuperMarkdownDivider",
    },
    links = {
      enabled = true,
      icon = "󰌹 ",
      hl = "SuperMarkdownLink",
    },
  },

  -- Mermaid diagram options
  mermaid = {
    enabled = true,
    inline = true, -- automatically render diagram in line inside the active buffer
    conceal_code = false, -- optionally conceal raw mermaid code block lines
    backend = "auto", -- "auto" (kitty/icat or ascii), "kitty", "ascii", "browser"
    api_url = "https://mermaid.ink/svg/",
    theme = "dark", -- "default", "dark", "forest", "neutral"
    cache_dir = vim.fn.stdpath("cache") .. "/super_markdown/mermaid",
    preview_win = {
      width = 0.85,
      height = 0.85,
      border = "rounded",
    },
  },

  -- Table of Contents (TOC) options
  toc = {
    picker = "auto", -- "auto" (prefers telescope > snacks > vim.ui.select), "telescope", "snacks", "ui_select"
    show_line_numbers = true,
    show_icons = true,
    sidebar = {
      width = 36,
      position = "right", -- "left" or "right"
      auto_close = false, -- keep open while toggled even when clicking or jumping
      auto_sync = true,   -- track active heading on cursor move
    },
  },

  -- Editing helpers
  tools = {
    smart_lists = true,    -- auto continue list on <CR>
    auto_link_paste = true, -- paste URL over selection -> [text](url)
    table_helpers = true,  -- table formatting and tab navigation
  },

  -- Markdown folding options
  folds = {
    enabled = true,
    foldcolumn = "1",       -- "1", "2", "auto" ("0" to disable fold column)
    foldlevel = 99,        -- initial fold level: 99 opens all on open; 0 folds all
    foldopen = "-",        -- gutter symbol for open fold
    foldclose = "+",       -- gutter symbol for closed fold
    foldsep = "│",         -- gutter symbol for open fold separator line
    foldtext = true,       -- styled foldtext with heading icon and line count
  },

  -- Keybindings
  keymaps = {
    toggle_render = "<leader>mr",
    toc = "<leader>mo",
    toc_sidebar = "<leader>ms",
    mermaid_preview = "<leader>mp",
    toggle_checkbox = "<leader>mx",
    format_table = "<leader>mtf",
    follow_link = "<leader>ml",
    fold_all = "<leader>mzM",
    unfold_all = "<leader>mzR",
    fold_toggle = "<leader>mza",
    table_next = "<Tab>",
    table_prev = "<S-Tab>",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
end

return M
