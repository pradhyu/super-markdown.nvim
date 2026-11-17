-- tests/test_mermaid_parity.lua
-- Comprehensive Verification of Mermaid Rendering with Termaid & Internal Engine Parity

local termaid = require("super-markdown.mermaid.termaid")
local ascii = require("super-markdown.mermaid.ascii")
local mermaid = require("super-markdown.mermaid")
local preview_pane = require("super-markdown.preview_pane")
local config = require("super-markdown.config")
local sm_main = require("super-markdown")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("  [PASS] " .. msg)
  else
    failed = failed + 1
    print("  [FAIL] " .. msg)
  end
end

print("==================================================================")
print("     super-markdown.nvim Mermaid Rendering Parity Suite           ")
print("==================================================================")

-- 1. Verify Termaid detection
print("\n--- 1. Termaid Availability & CLI Detection ---")
check(termaid.is_available() == true, "Termaid executable is detected and available in environment")
local cmd = termaid.get_command()
check(type(cmd) == "table" and #cmd >= 1, "Resolved valid termaid command table: " .. vim.inspect(cmd))

-- 2. Test All 18 Diagram Types across both Termaid and Internal Engine
print("\n--- 2. Full 18 Diagram Types Parity Verification ---")
local test_diagrams = {
  ["1. Flowchart (TD/TB)"] = [[flowchart TD
    A[Start] --> B{Verify?}
    B -->|Yes| C[Success]
    B -->|No| D[Retry]
]],
  ["2. Flowchart (LR Multi-Branch)"] = [[flowchart LR
    Client --> API --> DB
    API --> Cache
]],
  ["3. Flowchart (Nested Subgraphs)"] = [[flowchart LR
    subgraph G1[Frontend Tier]
      direction LR
      UI --> CDN
    end
    subgraph G2[Backend Tier]
      direction LR
      Gateway --> Microservice
    end
    CDN --> Gateway
]],
  ["4. Sequence Diagram"] = [[sequenceDiagram
    autonumber
    Client->>Server: Request Data
    Server-->>Client: Return 200 OK
]],
  ["5. Class Diagram"] = [[classDiagram
    Shape <|-- Circle
    Shape <|-- Square
    Shape : +int area()
]],
  ["6. State Diagram"] = [[stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Event
    Processing --> Idle: Done
    Processing --> [*]
]],
  ["7. Entity-Relationship (ER)"] = [[erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ ITEM : contains
]],
  ["8. Git Graph"] = [[gitGraph
    commit
    branch develop
    checkout develop
    commit
    checkout main
    merge develop
]],
  ["9. Gantt Chart"] = [[gantt
    title Release 1.0 Roadmap
    dateFormat YYYY-MM-DD
    section Phase 1
    Spec & Design :done, 2026-01-01, 2026-01-10
    Core Engine   :active, 2026-01-11, 2026-01-25
]],
  ["10. Pie Chart"] = [[pie title Resource Allocation
    "Compute" : 50
    "Storage" : 30
    "Network" : 20
]],
  ["11. Mindmap"] = [[mindmap
    root((Application))
      Architecture
        Clean Architecture
        Event Driven
      Testing
        Unit
        E2E
]],
  ["12. Timeline"] = [[timeline
    title Project Milestones
    2024 : Scaffolding
    2025 : Core Engine
    2026 : Production Rollout
]],
  ["13. Quadrant Chart"] = [[quadrantChart
    title Risk vs Impact
    x-axis Low Impact --> High Impact
    y-axis Low Risk --> High Risk
    Refactor: [0.3, 0.4]
    Migration: [0.8, 0.85]
]],
  ["14. XYChart"] = [[xychart-beta
    title "Monthly Active Users"
    x-axis [Jan, Feb, Mar, Apr]
    y-axis "Users (k)" 0 --> 100
    bar [20, 45, 75, 90]
]],
  ["15. User Journey"] = [[journey
    title User Onboarding Experience
    section Registration
      Visit Landing: 5: User
      Sign Up Form: 3: User
      Email Confirm: 4: User
]],
  ["16. Kanban"] = [[kanban
    Backlog
      [Research Task]
    In Progress
      [Implement Parity Suite]
    Complete
      [Termaid Module]
]],
  ["17. Packet Diagram"] = [[packet-beta
    0-15: "Source Port"
    16-31: "Destination Port"
    32-63: "Sequence"
]],
  ["18. Block Diagram"] = [[block-beta
    columns 3
    A["Input"] B["Processor"] C["Output"]
]]
}

for d_name, d_code in pairs(test_diagrams) do
  -- Termaid verification
  local t_ok, t_res = termaid.render(d_code, { width = 100 })
  check(t_ok and t_res and #t_res.text_lines > 0, d_name .. " renders via Termaid (" .. (t_res and #t_res.text_lines or 0) .. " lines)")
  check(t_res.is_styled == true and #t_res.virt_lines == #t_res.text_lines, d_name .. " has synchronized styled extmark lines")

  -- Internal fallback verification
  local i_lines = ascii.render(d_code, { max_width = 100 })
  check(i_lines and #i_lines > 0, d_name .. " renders via Internal pure-Lua fallback (" .. #i_lines .. " lines)")
end

-- 3. Test Style Mapping & Token Granularity
print("\n--- 3. Termaid Styled-JSON Token to Extmark Mapping ---")
local test_sample = [[flowchart LR
    A[Client UI] -->|HTTP POST| B[Gateway]
    B --> C[Database]
]]
local ok_sample, res_sample = termaid.render(test_sample)
check(ok_sample, "Sample flowchart rendered")
local has_border, has_arrow, has_label = false, false, false
for _, row in ipairs(res_sample.virt_lines) do
  for _, chunk in ipairs(row) do
    local hl = chunk[2]
    if hl == "SuperMarkdownTableBorder" then has_border = true end
    if hl == "SuperMarkdownMermaidArrow" then has_arrow = true end
    if hl == "SuperMarkdownMermaidNodeLabel" then has_label = true end
  end
end
check(has_border, "Extmark chunks include SuperMarkdownTableBorder for boxes")
check(has_arrow, "Extmark chunks include SuperMarkdownMermaidArrow for connectors & heads")
check(has_label, "Extmark chunks include SuperMarkdownMermaidNodeLabel for node text")

-- 4. Test In-Buffer Ephemeral Extmark Live Rendering
print("\n--- 4. In-Buffer Rendering with Both Engines ---")
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
  "# Architecture Spec",
  "```mermaid",
  "flowchart LR",
  "    A[Service A] --> B[Service B]",
  "```",
  "Normal prose paragraph following diagram.",
})

-- Test with termaid engine
sm_main.set_mermaid_renderer("termaid")
mermaid.render_inline(test_buf)
local marks_termaid = vim.api.nvim_buf_get_extmarks(test_buf, mermaid.get_namespace(), 0, -1, { details = true })
check(#marks_termaid >= 2, "In-buffer extmarks attached using Termaid engine (" .. #marks_termaid .. " marks)")

-- Test with internal engine
sm_main.set_mermaid_renderer("internal")
mermaid.render_inline(test_buf)
local marks_internal = vim.api.nvim_buf_get_extmarks(test_buf, mermaid.get_namespace(), 0, -1, { details = true })
check(#marks_internal >= 2, "In-buffer extmarks attached using Internal engine (" .. #marks_internal .. " marks)")

-- Restore auto mode
sm_main.set_mermaid_renderer("auto")
check(mermaid.get_active_renderer() == "termaid", "Auto mode prefers Termaid when installed")

-- 5. Test Side Preview Pane Synchronization
print("\n--- 5. Side Preview Pane Mermaid Rendering ---")
preview_pane.open({ bufnr = test_buf })
local p_win = preview_pane.get_window()
check(p_win ~= nil and vim.api.nvim_win_is_valid(p_win), "Preview pane opened for buffer with Mermaid block")
local p_buf = vim.api.nvim_win_get_buf(p_win)
local p_lines = vim.api.nvim_buf_get_lines(p_buf, 0, -1, false)
local found_preview_mermaid = false
for _, l in ipairs(p_lines) do
  if l:find("Service A") or l:find("Service B") or l:find("Mermaid Diagram") then
    found_preview_mermaid = true
    break
  end
end
check(found_preview_mermaid, "Preview pane contains rendered Mermaid diagram")
preview_pane.close()

-- 6. Test Options Propagation (Width, Padding, Arrow Style)
print("\n--- 6. Termaid Options Customization ---")
local ok_opt, res_opt = termaid.render(test_sample, {
  padding_x = 4,
  padding_y = 2,
  gap = 3,
  arrow_style = "pointer",
  width = 80,
})
check(ok_opt and #res_opt.text_lines > 0, "Custom padding_x, padding_y, gap, and width accepted cleanly")

-- 7. Test Inbuilt Native Engine Fidelity & Dedicated Diagram Renderers
print("\n--- 7. Inbuilt Native Pure-Lua Engine Fidelity Verification ---")

-- 7.1 Kanban
local kanban_out = ascii.render([[kanban
  Backlog
    [Task 1]
  In Progress
    [Task 2]
  Done
    [Task 3]
]], { max_width = 80 })
local kanban_str = table.concat(kanban_out, "\n")
check(kanban_str:find("Backlog %(1%)") ~= nil and kanban_str:find("In Progress %(1%)") ~= nil and kanban_str:find("Done %(1%)") ~= nil, "Inbuilt Kanban produces formatted multi-column board with card counts")
check(kanban_str:find("Task 1") ~= nil and kanban_str:find("Task 2") ~= nil, "Inbuilt Kanban retains individual task labels")

-- 7.2 Quadrant Chart
local quad_out = ascii.render([[quadrantChart
  title Parity Matrix
  x-axis Low Effort --> High Effort
  y-axis Low Value --> High Value
  quadrant-1 Quick Wins
  quadrant-2 Major Projects
  quadrant-3 Fill-ins
  quadrant-4 Thankless Tasks
  Optimizer: [0.8, 0.9]
  Bugfix: [0.2, 0.4]
]], { max_width = 80 })
local quad_str = table.concat(quad_out, "\n")
check(quad_str:find("Q1: Quick Wins") ~= nil and quad_str:find("Q2: Major Projects") ~= nil, "Inbuilt Quadrant renders 2x2 labeled matrix")
check(quad_str:find("Optimizer") ~= nil and quad_str:find("Bugfix") ~= nil, "Inbuilt Quadrant maps data points to corresponding quadrants")

-- 7.3 Packet Diagram
local packet_out = ascii.render([[packet-beta
  0-15: "Source Port"
  16-31: "Destination Port"
  32-63: "Sequence Number"
]], { max_width = 80 })
local packet_str = table.concat(packet_out, "\n")
check(packet_str:find("%[0%.%.15%]") ~= nil and packet_str:find("Source Port") ~= nil, "Inbuilt Packet renders RFC-style bit offset headers and field boxes")
check(packet_str:find("%(16 bits%)") ~= nil or packet_str:find("%(32 bits%)") ~= nil, "Inbuilt Packet calculates and displays bit lengths")

-- 7.4 User Journey
local journey_out = ascii.render([[journey
  title Developer Onboarding
  section Setup
    Install Neovim: 5: Dev
    Configure Plugins: 4: Dev
]], { max_width = 80 })
local journey_str = table.concat(journey_out, "\n")
check(journey_str:find("★★★★★ %(5/5%)") ~= nil, "Inbuilt User Journey displays visual satisfaction stars")
check(journey_str:find("%[Dev%]") ~= nil, "Inbuilt User Journey displays actor badges")

-- 7.5 Treemap
local treemap_out = ascii.render([[treemap
  Disk
    Code: 70
    Data: 30
]], { max_width = 80 })
local treemap_str = table.concat(treemap_out, "\n")
check(treemap_str:find("70%%") ~= nil and treemap_str:find("30%%") ~= nil, "Inbuilt Treemap calculates percentages")
check(treemap_str:find("█") ~= nil, "Inbuilt Treemap renders proportional visual bar meters")

-- 7.6 Sankey
local sankey_out = ascii.render([[sankey-beta
  ServiceA,ServiceB,100
  ServiceB,Database,80
]], { max_width = 80 })
local sankey_str = table.concat(sankey_out, "\n")
check(sankey_str:find("ServiceA") ~= nil and sankey_str:find("──%[ 100 %]──▶") ~= nil, "Inbuilt Sankey displays directed weighted flows")

-- 7.7 Block Diagram
local block_out = ascii.render([[block-beta
  columns 3
  A["Input"] B["Compute"] C["Output"]
]], { max_width = 80 })
local block_str = table.concat(block_out, "\n")
check(block_str:find("Input") ~= nil and block_str:find("Compute") ~= nil and block_str:find("Output") ~= nil, "Inbuilt Block diagram renders structured block units")

print(string.format("\n=================================================================="))
print(string.format("   Parity Suite Complete: %d Passed, %d Failed (Total: %d)", passed, failed, passed + failed))
print(string.format("=================================================================="))

if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
