package = "einstein"
version = "scm-1"
source = {
   url = "git+https://github.com/qompassai/Einstein-GPT-for-Developers",
}
description = {
   summary = "Native Neovim client for the Einstein GPT gateway (Agentforce Vibes portable core)",
   detailed = "Dependency-free Neovim plugin that ports the portable core of the "
      .. "Agentforce Vibes / Einstein GPT VS Code extension: prompt-driven code "
      .. "generation, explanation, and Apex/LWC test generation over the gateway's "
      .. "chat/generations endpoint, authenticated from the Salesforce CLI org session.",
   homepage = "https://github.com/qompassai/Einstein-GPT-for-Developers",
   license = "BSD-3-Clause",
}
dependencies = {
   "lua >= 5.1",
}
build = {
   type = "builtin",
   modules = {
      ["einstein"] = "lua/einstein/init.lua",
      ["einstein.auth"] = "lua/einstein/auth.lua",
      ["einstein.client"] = "lua/einstein/client.lua",
      ["einstein.config"] = "lua/einstein/config.lua",
      ["einstein.prompts"] = "lua/einstein/prompts.lua",
      ["einstein.ui"] = "lua/einstein/ui.lua",
   },
}
