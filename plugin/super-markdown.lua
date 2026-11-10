if vim.g.loaded_super_markdown then
  return
end
vim.g.loaded_super_markdown = true

local subcommands = {
  toggle = function() require("super-markdown").toggle() end,
  focus = function(args) require("super-markdown").focus_toggle(nil, args and args[2]) end,
  focus_toggle = function(args) require("super-markdown").focus_toggle(nil, args and args[2]) end,
  zen = function() require("super-markdown").zen() end,
  zen_toggle = function() require("super-markdown").zen() end,
  preview = function() require("super-markdown").preview_pane() end,
  preview_pane = function() require("super-markdown").preview_pane() end,
  preview_only = function(args) require("super-markdown").reader_mode(args and args[2]) end,
  reader = function(args) require("super-markdown").reader_mode(args and args[2]) end,
  reader_mode = function(args) require("super-markdown").reader_mode(args and args[2]) end,
  toggle_editor = function() require("super-markdown").toggle_editor() end,
  hide_editor = function() require("super-markdown").hide_editor() end,
  show_editor = function() require("super-markdown").show_editor() end,
  preview_sync = function(args) require("super-markdown").preview_sync(args and args[2]) end,
  auto_refresh = function(args) require("super-markdown").auto_refresh(args and args[2]) end,
  render = function() require("super-markdown").render() end,
  clear = function() require("super-markdown").clear() end,
  reload = function() require("super-markdown").reload() end,
  toc = function() require("super-markdown").toc() end,
  toc_sidebar = function(args) require("super-markdown").toc_sidebar(args and args[2]) end,
  toc_sidebar_pos = function(args) require("super-markdown").toc_sidebar_pos(args and args[2]) end,
  toc_top = function(args) require("super-markdown").set_scroll_to_top(args and args[2]) end,
  scroll_to_top = function(args) require("super-markdown").set_scroll_to_top(args and args[2]) end,
  sticky = function() require("super-markdown").sticky_toggle() end,
  sticky_toggle = function() require("super-markdown").sticky_toggle() end,
  sticky_enable = function() require("super-markdown").sticky_enable() end,
  sticky_disable = function() require("super-markdown").sticky_disable() end,
  mermaid = function() require("super-markdown").mermaid_preview() end,
  checkbox = function() require("super-markdown").checkbox_toggle() end,
  table_format = function() require("super-markdown").table_format() end,
  link = function() require("super-markdown").follow_link() end,
  preview_ref = function() require("super-markdown").preview_ref() end,
  fold_all = function() require("super-markdown").fold_all() end,
  fold_toc = function() require("super-markdown").fold_toc() end,
  unfold_all = function() require("super-markdown").unfold_all() end,
  fold_toggle = function() require("super-markdown").fold_toggle() end,
  collapse_all = function() require("super-markdown").collapse_all() end,
  expand_all = function() require("super-markdown").expand_all() end,
  collapse_header = function(args) require("super-markdown").collapse_header(args and tonumber(args[2])) end,
  expand_header = function(args) require("super-markdown").expand_header(args and tonumber(args[2])) end,
  fold_more = function() require("super-markdown").fold_more() end,
  fold_less = function() require("super-markdown").fold_less() end,
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
  diff = function() require("super-markdown").diff_toggle() end,
  spec_diff = function() require("super-markdown").diff_toggle() end,
  diff_hud = function() require("super-markdown").diff_dashboard() end,
  diff_dashboard = function() require("super-markdown").diff_dashboard() end,
  next_change = function() require("super-markdown").next_change() end,
  prev_change = function() require("super-markdown").prev_change() end,
  next_req = function() require("super-markdown").next_requirement() end,
  prev_req = function() require("super-markdown").prev_requirement() end,
  next_question = function() require("super-markdown").next_question() end,
  prev_question = function() require("super-markdown").prev_question() end,
  next_blocker = function() require("super-markdown").next_blocker() end,
  prev_blocker = function() require("super-markdown").prev_blocker() end,
  next_task = function() require("super-markdown").next_task() end,
  prev_task = function() require("super-markdown").prev_task() end,
  next_risk = function() require("super-markdown").next_risk() end,
  prev_risk = function() require("super-markdown").prev_risk() end,
  next_fluff = function() require("super-markdown").next_fluff() end,
  prev_fluff = function() require("super-markdown").prev_fluff() end,
  next_scenario = function() require("super-markdown").next_scenario() end,
  prev_scenario = function() require("super-markdown").prev_scenario() end,
  next_review = function() require("super-markdown").next_review() end,
  prev_review = function() require("super-markdown").prev_review() end,
  skim = function() require("super-markdown").skim() end,
  skim_toggle = function() require("super-markdown").skim_toggle() end,
  eyeball = function() require("super-markdown").eyeball() end,
  eyeball_hud = function() require("super-markdown").eyeball_hud() end,
  review_approve = function() require("super-markdown").review_approve() end,
  review_question = function(args) require("super-markdown").review_question(nil, args and args[2]) end,
  review_reject = function(args) require("super-markdown").review_reject(nil, args and args[2]) end,
  review_comment = function(args) require("super-markdown").review_comment(nil, args and args[2]) end,
  review_approve_all = function() require("super-markdown").review_approve_all() end,
  review_reject_all = function(args) require("super-markdown").review_reject_all(nil, args and args[2]) end,
  review_export = function() require("super-markdown").review_export() end,
  breadcrumb = function() require("super-markdown").breadcrumb() end,
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
    elseif #words == 3 then
      local sub = words[2]
      if sub == "toc_sidebar" or sub == "toc_sidebar_pos" or sub == "reader" or sub == "reader_mode" or sub == "preview_only" then
        local opts = { "left", "right", "flip" }
        local matches = {}
        for _, opt in ipairs(opts) do
          if vim.startswith(opt, words[3] or "") then
            table.insert(matches, opt)
          end
        end
        return matches
      elseif sub == "focus" or sub == "focus_toggle" then
        local opts = { "toggle", "on", "off", "toc", "root", "section", "block" }
        local matches = {}
        for _, opt in ipairs(opts) do
          if vim.startswith(opt, words[3] or "") then
            table.insert(matches, opt)
          end
        end
        return matches
      elseif sub == "auto_refresh" then
        local opts = { "toggle", "on", "off", "500", "1000", "2000" }
        local matches = {}
        for _, opt in ipairs(opts) do
          if vim.startswith(opt, words[3] or "") then
            table.insert(matches, opt)
          end
        end
        return matches
      end
    end
  end,
  desc = "SuperMarkdown command suite",
})
