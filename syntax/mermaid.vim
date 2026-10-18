" Vim syntax file
" Language: Mermaid (Diagrams and Flowcharts)
" Maintainer: super-markdown.nvim

if exists("b:current_syntax")
  finish
endif

syn case match

syn keyword mermaidKeyword graph flowchart sequenceDiagram classDiagram stateDiagram stateDiagram-v2 erDiagram gantt pie gitGraph journey mindmap quadrantChart xychart-beta timeline c4Context sankey-beta
syn keyword mermaidKeyword subgraph end direction classDef class style linkStyle click interpolate
syn keyword mermaidKeyword autonumber actor participant as Note over loop alt else opt par critical break rect activate deactivate
syn keyword mermaidKeyword state fork join choice commit branch checkout merge tag title accTitle accDescr

syn keyword mermaidType TD TB BT RL LR

syn match mermaidComment "%%.*$" display contains=@Spell
syn region mermaidString start=+"+ skip=+\\"+ end=+"+ display

syn match mermaidArrow "-->\|-->>\|->\|->>\|-\.->\|-\.-\|==>\|===\|---\|--x\|--)\|<-+>\|<|--\|--|>\|<--\|<-" display
syn match mermaidEdgeLabel "|[^|]\+|" display
syn match mermaidShape "\[.\{-}\]\|(.\{-})\|{.\{-}}" display
syn match mermaidHexColor "#[0-9a-fA-F]\+" display
syn match mermaidNumber "\<\d\+\>" display

hi def link mermaidKeyword SuperMarkdownMermaidKeyword
hi def link mermaidType SuperMarkdownMermaidType
hi def link mermaidComment SuperMarkdownMermaidComment
hi def link mermaidString SuperMarkdownMermaidString
hi def link mermaidArrow SuperMarkdownMermaidArrow
hi def link mermaidEdgeLabel SuperMarkdownMermaidEdgeLabel
hi def link mermaidShape SuperMarkdownMermaidNodeLabel
hi def link mermaidHexColor SuperMarkdownMermaidNumber
hi def link mermaidNumber SuperMarkdownMermaidNumber

let b:current_syntax = "mermaid"
