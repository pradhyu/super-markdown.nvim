if vim.g.loaded_super_markdown then
  return
end
vim.g.loaded_super_markdown = true

local subcommands = {
  toggle = function() require("super-markdown").toggle() end,
  render = function() require("super-markdown").render() end,
  clear = function() require("super-markdown").clear() end,
  reload = function() require("super-markdown").reload() end,
  toc = function() require("super-markdown").toc() end,
  toc_sidebar = function() require("super-markdown").toc_sidebar() end,
  mermaid = function() require("super-markdown").mermaid_preview() end,
  checkbox = function() require("super-markdown").checkbox_toggle() end,
  table_format = function() require("super-markdown").table_format() end,
  link = function() require("super-markdown").follow_link() end,
  preview_ref = function() require("super-markdown").preview_ref() end,
  fold_all = function() require("super-markdown").fold_all() end,
  fold_toc = function() require("super-markdown").fold_toc() end,
  unfold_all = function() require("super-markdown").unfold_all() end,
  fold_toggle = function() require("super-markdown").fold_toggle() end,
  fold_level = function(args) require("super-markdown").fold_level(args and args[2]) end,
  spec_dashboard = function() require("super-markdown").spec_dashboard() end,
  spec_pick = function(args) require("super-markdown").spec_pick(args and args[2]) end,
  spec_lint = function() require("super-markdown").spec_lint() end,
  spec_clear_lint = function() require("super-markdown").spec_clear_lint() end,
  spec_new = function(args) require("super-markdown").spec_new(args and args[2]) end,
  spec_status = function() require("super-markdown").spec_status() end,
  llm_context = function(args) require("super-markdown").llm_context(nil, args and args[2] == "all") end,
  llm_code = function() require("super-markdown").llm_code() end,
  llm_tests = function() require("super-markdown").llm_tests() end,
  llm_review = function() require("super-markdown").llm_review() end,
  run_block = function() require("super-markdown").run_block() end,
  clear_runs = function() require("super-markdown").clear_runs() end,
}

vim.api.nvim_create_user_command("SuperMarkdown", function(opts)
  local cmd = opts.fargs[1] or "toggle"
  local fn = subcommands[cmd]
  if fn then
    fn(opts.fargs)
  else
    vim.notify("SuperMarkdown: Unknown subcommand '" .. cmd .. "'", vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(_, line)
    local words = vim.split(line, "%s+")
    if #words <= 2 then
      local matches = {}
      for name, _ in pairs(subcommands) do
        if vim.startswith(name, words[2] or "") then
          table.insert(matches, name)
        end
      end
      table.sort(matches)
      return matches
    end
  end,
  desc = "SuperMarkdown command suite",
})
