-- einstein.nvim: prompt catalog for the portable extension flows.
-- SPDX-License-Identifier: BSD-3-Clause
--
-- The flows mirror the portable surface of the Agentforce Vibes /
-- Einstein GPT extension as documented in this repository: generate
-- code from a prompt, explain code, and test case generation for Apex
-- and for LWC Jest tests (see docs/Jest Test Generation/). The prompt
-- texts are this plugin's own; only the flow shapes come from the
-- product. Chat completions themselves ride the gateway's
-- chat/generations endpoint via einstein.client.

local M = {}

local CONTEXT_CHARS_MAX = 64000
local PROMPT_CHARS_MAX = 32000

---@type table<string, string>
local SYSTEM_PROMPTS = {
    explain = 'You are a senior Salesforce developer. Explain the provided code clearly and concisely: '
        .. 'its purpose, control flow, the data it reads and writes, and any risks or anti-patterns. '
        .. 'Answer in Markdown.',
    generate = 'You are a senior Salesforce developer. Write correct, production-quality Salesforce '
        .. 'code for the request. Prefer Apex and Lightning Web Components idioms, bulkification, and '
        .. 'secure CRUD/FLS handling. Return the code first, with brief notes only where essential.',
    generate_tests_apex = 'You are a senior Salesforce developer. Write Apex test classes for the '
        .. 'provided code: use @isTest, SeeAllData=false, meaningful assertions, positive and negative '
        .. 'cases, and bulk records. Return only the test code.',
    generate_tests_lwc = 'You are a senior Salesforce developer. Write Jest unit tests for the provided '
        .. 'Lightning web component following the @salesforce/sfdx-lwc-jest conventions: create the '
        .. 'element, mock Apex and wire adapters, and assert on the rendered DOM. Return only the test code.',
}

---Flow names in alphabetical order, for help and completion.
---@return string[]
function M.flow_names()
    local names = {}
    for name in pairs(SYSTEM_PROMPTS) do
        names[#names + 1] = name
    end
    table.sort(names)
    names[#names + 1] = 'chat'
    table.sort(names)
    return names
end

---Truncate text to a character budget, marking the cut (pure).
---@param text string
---@param limit integer
---@return string
local function truncate(text, limit)
    if #text <= limit then
        return text
    end
    return text:sub(1, limit) .. '\n... [truncated at ' .. limit .. ' characters]'
end

---Assemble the chat messages for one flow (pure, testable).
---@param flow string One of M.flow_names().
---@param request { prompt: string, context?: string, context_label?: string }
---@return table[]? messages, string? error
function M.messages_for(flow, request)
    assert(type(request) == 'table', 'einstein.prompts.messages_for: request must be a table')
    if flow ~= 'chat' and SYSTEM_PROMPTS[flow] == nil then
        return nil, 'unknown flow: ' .. tostring(flow)
    end
    local prompt = truncate(tostring(request.prompt or ''), PROMPT_CHARS_MAX)
    if prompt == '' then
        return nil, 'prompt is empty'
    end
    local user_content = prompt
    if request.context ~= nil and request.context ~= '' then
        local label = request.context_label or 'Context'
        local context = truncate(request.context, CONTEXT_CHARS_MAX)
        user_content = label .. ':\n```\n' .. context .. '\n```\n\n' .. prompt
    end
    local messages = {}
    local system = SYSTEM_PROMPTS[flow]
    if system ~= nil then
        messages[#messages + 1] = { content = system, role = 'system' }
    end
    messages[#messages + 1] = { content = user_content, role = 'user' }
    return messages
end

return M
