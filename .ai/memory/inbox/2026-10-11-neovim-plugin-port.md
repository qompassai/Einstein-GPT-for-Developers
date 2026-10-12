# 2026-10-11 — Native Neovim port (einstein.nvim) built

Overnight campaign pass. Findings and build record; full report lives in the
campaign workspace (overnight-2026-10-11/einstein.md).

## Survey facts
- This repo is the product/docs repo for the extension; the extension source
  is not in it (and the current upstream source repo is private). API surface
  was extracted from the shipped VSIX (Open VSX, salesforcedx-einstein-gpt
  4.35.0, dist/extension.js).
- Gateway: POST {base}/chat/generations; base by environment, prod =
  https://api.salesforce.com/ai/gpt/v1. Headers include
  x-sfdc-app-context: EinsteinGPT and x-sfdc-core-tenant-id: <org id>.
  Response envelope: generation_details.generations[1].content.
  Default model: sfdc_ai__DefaultBedrockAnthropicClaude46Sonnet.
- Auth = authorized org session; resolved here from `sf org display --json`.

## Built
- plugin/einstein.lua + lua/einstein/{init,config,auth,client,prompts,ui}.lua
  (Tiger Style, LuaCATS, no dependencies), einstein-scm-1.rockspec,
  spec/*_spec.lua (busted 17/17), .luarc.json, selene.toml + lua51.yml +
  vim.yml (selene 0.31 cannot chain builtin+file stds; file-only chain).
- Commands: EinsteinAuth, EinsteinChat, EinsteinExplain, EinsteinGenerate,
  EinsteinGenerateTests, EinsteinModels.
- Gates: luacheck 0/0, StyLua canonical clean, LuaLS 0 and selene 0 per file
  (first-open settle probes), headless load smoke incl. structured
  not_authenticated without a session, luarocks lint + throwaway-tree make.
- SCIP: generated with ~/.local/bin/scip-lua (--corpus/--out-dir); the index
  is a build artifact and is not committed.

## Out of scope (VS Code-host surfaces)
Chat webview, orchestration board, inline autocomplete provider, Dev Agent
conversations, MCP/skills settings UIs.
