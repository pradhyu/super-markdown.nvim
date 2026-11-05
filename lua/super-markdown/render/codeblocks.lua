local M = {}

local TS_LANG_ALIASES = {
  sh = "bash",
  zsh = "bash",
  shell = "bash",
  console = "bash",
  js = "javascript",
  jsx = "javascript",
  ts = "typescript",
  py = "python",
  yml = "yaml",
  md = "markdown",
  rs = "rust",
  golang = "go",
  ["c++"] = "cpp",
  cxx = "cpp",
  hpp = "cpp",
  h = "c",
}

local LEXICAL_KEYWORDS = {
  ["local"] = true, ["function"] = true, ["return"] = true, ["if"] = true, ["then"] = true,
  ["else"] = true, ["elseif"] = true, ["end"] = true, ["for"] = true, ["in"] = true,
  ["do"] = true, ["while"] = true, ["repeat"] = true, ["until"] = true, ["break"] = true,
  ["continue"] = true, ["def"] = true, ["class"] = true, ["import"] = true, ["from"] = true,
  ["as"] = true, ["pass"] = true, ["yield"] = true, ["async"] = true, ["await"] = true,
  ["with"] = true, ["try"] = true, ["except"] = true, ["finally"] = true, ["raise"] = true,
  ["const"] = true, ["let"] = true, ["var"] = true, ["export"] = true, ["default"] = true,
  ["new"] = true, ["typeof"] = true, ["instanceof"] = true, ["switch"] = true, ["case"] = true,
  ["fn"] = true, ["pub"] = true, ["mut"] = true, ["struct"] = true, ["enum"] = true,
  ["impl"] = true, ["trait"] = true, ["use"] = true, ["mod"] = true, ["match"] = true,
  ["where"] = true, ["crate"] = true, ["self"] = true, ["super"] = true, ["func"] = true,
  ["package"] = true, ["defer"] = true, ["go"] = true, ["select"] = true, ["interface"] = true,
  ["public"] = true, ["private"] = true, ["protected"] = true, ["static"] = true, ["final"] = true,
  ["abstract"] = true, ["extends"] = true, ["implements"] = true, ["throws"] = true, ["throw"] = true,
  ["record"] = true, ["synchronized"] = true, ["volatile"] = true, ["this"] = true,
  ["type"] = true, ["SELECT"] = true, ["FROM"] = true, ["WHERE"] = true, ["INSERT"] = true,
  ["INTO"] = true, ["VALUES"] = true, ["UPDATE"] = true, ["SET"] = true, ["DELETE"] = true,
  ["JOIN"] = true, ["LEFT"] = true, ["INNER"] = true, ["ON"] = true, ["GROUP"] = true,
  ["BY"] = true, ["ORDER"] = true, ["LIMIT"] = true, ["CREATE"] = true, ["TABLE"] = true,
  ["AND"] = true, ["OR"] = true, ["NOT"] = true, ["NULL"] = true, ["PRIMARY"] = true, ["KEY"] = true,
}

local LEXICAL_LITERALS = {
  ["true"] = true, ["false"] = true, ["nil"] = true, ["null"] = true,
  ["True"] = true, ["False"] = true, ["None"] = true, ["undefined"] = true,
}

local LEXICAL_TYPES = {
  ["string"] = true, ["number"] = true, ["boolean"] = true, ["table"] = true, ["any"] = true,
  ["void"] = true, ["int"] = true, ["long"] = true, ["short"] = true, ["byte"] = true,
  ["float"] = true, ["double"] = true, ["char"] = true,
  ["bool"] = true, ["usize"] = true, ["isize"] = true, ["u8"] = true, ["u16"] = true,
  ["u32"] = true, ["u64"] = true, ["i8"] = true, ["i16"] = true, ["i32"] = true, ["i64"] = true,
  ["f32"] = true, ["f64"] = true, ["str"] = true, ["String"] = true, ["Vec"] = true,
  ["Option"] = true, ["Result"] = true, ["Map"] = true, ["List"] = true, ["Dict"] = true,
  ["INT"] = true, ["INTEGER"] = true, ["VARCHAR"] = true, ["TEXT"] = true, ["BOOLEAN"] = true,
  ["TIMESTAMP"] = true, ["SERIAL"] = true, ["UUID"] = true, ["JSONB"] = true,
}

local function has_treesitter_parser(lang)
  if not lang or lang == "" then return false end
  local ts_lang = TS_LANG_ALIASES[lang] or lang
  if vim.treesitter and vim.treesitter.language and vim.treesitter.language.add then
    local ok, res = pcall(vim.treesitter.language.add, ts_lang)
    if ok and res ~= false then
      return true
    end
  end
  local ok_p, parser = pcall(vim.treesitter.get_string_parser, "", ts_lang)
  return ok_p and parser ~= nil
end

local function apply_lexical_highlights(bufnr, ns_id, lnum, line, lang)
  local n = #line
  if n == 0 then return end

  local c_start = nil
  if lang == "lua" or lang == "sql" then
    c_start = line:find("%-%-")
  elseif lang == "python" or lang == "bash" or lang == "sh" or lang == "zsh" or lang == "yaml" or lang == "toml" then
    c_start = line:find("#")
  else
    c_start = line:find("//") or line:find("#")
  end

  local code_end = c_start and (c_start - 1) or n
  local idx = 1

  while idx <= code_end do
    local ch = line:sub(idx, idx)
    if ch == '"' or ch == "'" or ch == "`" then
      local q = ch
      local j = idx + 1
      while j <= code_end do
        local cj = line:sub(j, j)
        if cj == "\\" then
          j = j + 2
        elseif cj == q then
          j = j + 1
          break
        else
          j = j + 1
        end
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, idx - 1, {
        end_col = math.min(j - 1, code_end),
        hl_group = "SuperMarkdownMermaidString",
        priority = 95,
      })
      idx = j
    elseif ch == "@" and line:sub(idx + 1, idx + 1):match("[%a_]") then
      local _, ann_e = line:find("^@[%a_][%w_]*", idx)
      if ann_e then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, idx - 1, {
          end_col = math.min(ann_e, code_end),
          hl_group = "SuperMarkdownMermaidNodeId",
          priority = 95,
        })
        idx = ann_e + 1
      else
        idx = idx + 1
      end
    elseif ch:match("%d") and (idx == 1 or not line:sub(idx - 1, idx - 1):match("[%w_]")) then
      local _, num_e = line:find("^[%da-fA-FxX%.L]+", idx)
      if num_e then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, idx - 1, {
          end_col = math.min(num_e, code_end),
          hl_group = "SuperMarkdownMermaidNumber",
          priority = 95,
        })
        idx = num_e + 1
      else
        idx = idx + 1
      end
    elseif ch:match("[%a_]") then
      local _, id_e, word = line:find("^([%a_][%w_]*)", idx)
      if id_e and word then
        local next_ch = line:sub(id_e + 1, id_e + 1)
        local hl = nil
        if LEXICAL_KEYWORDS[word] then
          hl = "SuperMarkdownMermaidKeyword"
        elseif LEXICAL_LITERALS[word] then
          hl = "SuperMarkdownMermaidNumber"
        elseif LEXICAL_TYPES[word] or word:match("^[A-Z][%w_]*$") then
          hl = "SuperMarkdownMermaidType"
        elseif next_ch == "(" then
          hl = "SuperMarkdownH1"
        end
        if hl then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, idx - 1, {
            end_col = id_e,
            hl_group = hl,
            priority = 95,
          })
        end
        idx = id_e + 1
      else
        idx = idx + 1
      end
    else
      idx = idx + 1
    end
  end

  if c_start then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, lnum, c_start - 1, {
      end_col = n,
      hl_group = "SuperMarkdownMermaidComment",
      priority = 95,
    })
  end
end

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
      use_lexical = (lang_clean ~= "" and lang_clean ~= "mermaid" and not has_treesitter_parser(lang_clean)),
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
    if in_codeblock.use_lexical then
      apply_lexical_highlights(bufnr, ns_id, lnum, line, in_codeblock.lang)
    end
    return in_codeblock
  end

  return in_codeblock
end

return M
