-- einstein.nvim: native Neovim client for the Einstein GPT gateway.
-- SPDX-License-Identifier: BSD-3-Clause
--
-- A dependency-free port of the portable core of the Agentforce Vibes /
-- Einstein GPT VS Code extension: prompt-driven code generation, code
-- explanation, and test case generation for Apex and LWC, riding the
-- gateway's chat/generations endpoint (see einstein.client) with the
-- org session resolved from the Salesforce CLI (see einstein.auth).
-- VS Code-host surfaces (chat webview, orchestration board, inline
-- completion provider, MCP settings UI) are out of scope by design;
-- the README's Neovim section records the full boundary.

local auth = require('einstein.auth')
local client = require('einstein.client')
local config = require('einstein.config')
local prompts = require('einstein.prompts')
local ui = require('einstein.ui')

local M = {}

---@type EinsteinConfig?
local active_config = nil
local commands_registered = false

---Return the active configuration, resolving defaults on first use.
---@return EinsteinConfig
local function cfg()
    if active_config == nil then
        local resolved, err = config.resolve(nil)
        assert(resolved ~= nil, err or 'einstein: configuration failed')
        active_config = resolved
    end
    return active_config
end

---Collect buffer text for use as flow context.
---@param bufnr integer
---@param line_first? integer First line (1-based) of an explicit range.
---@param line_last? integer Last line (1-based) of an explicit range.
---@return string
local function buffer_context(bufnr, line_first, line_last)
    local lines
    if line_first ~= nil and line_last ~= nil and line_last >= line_first then
        lines = vim.api.nvim_buf_get_lines(bufnr, line_first - 1, line_last, false)
    else
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
    return table.concat(lines, '\n')
end

---Run one flow end to end: auth, request, display.
---@param flow string
---@param prompt_text string
---@param context? string
---@param context_label? string
local function run_flow(flow, prompt_text, context, context_label)
    local messages, err = prompts.messages_for(flow, {
        context = context,
        context_label = context_label,
        prompt = prompt_text,
    })
    if messages == nil then
        ui.notify_error({ code = 'invalid_request', message = err or 'invalid request' })
        return
    end
    vim.notify('einstein: contacting the gateway...', vim.log.levels.INFO)
    auth.resolve(cfg(), function(session, auth_err)
        if session == nil then
            ui.notify_error(auth_err or { code = 'not_authenticated', message = 'not authenticated' })
            return
        end
        client.chat(cfg(), session, messages, function(text, chat_err)
            if text == nil then
                ui.notify_error(chat_err or { code = 'unexpected_response', message = 'empty response' })
                return
            end
            ui.show_result('Einstein: ' .. flow, text)
        end)
    end)
end

---Resolve the prompt for a command: explicit args win, else ask.
---@param args string Command argument string, possibly empty.
---@param label string Input prompt used when args are empty.
---@param callback fun(text?: string)
local function with_prompt(args, label, callback)
    local trimmed = vim.trim(args or '')
    if trimmed ~= '' then
        callback(trimmed)
        return
    end
    ui.input_prompt(label, callback)
end

---Implementation of :EinsteinAuth.
local function command_auth()
    auth.status(cfg(), function(view)
        if not view.authenticated then
            ui.notify_error(view.error or { code = 'not_authenticated', message = 'not authenticated' })
            return
        end
        local lines = {
            'authenticated via ' .. view.source,
            'username: ' .. (view.username ~= '' and view.username or '(from environment)'),
            'instance: ' .. view.instance_url,
            'org id: ' .. view.org_id,
            'gateway: ' .. cfg().base_url,
            'model: ' .. cfg().model,
        }
        ui.show_result('Einstein: auth status', table.concat(lines, '\n'))
    end)
end

---Implementation of :EinsteinModels.
local function command_models()
    local names = {}
    for name in pairs(config.MODELS) do
        names[#names + 1] = name
    end
    table.sort(names)
    local lines = { 'Default model: ' .. cfg().model, '' }
    for _, name in ipairs(names) do
        local marker = config.MODELS[name] == cfg().model and ' (active)' or ''
        lines[#lines + 1] = '- ' .. name .. ' = ' .. config.MODELS[name] .. marker
    end
    ui.show_result('Einstein: model catalog', table.concat(lines, '\n'))
end

---Register all user commands (idempotent).
local function register_commands()
    if commands_registered then
        return
    end
    commands_registered = true
    local create = vim.api.nvim_create_user_command
    create('EinsteinAuth', command_auth, { desc = 'Einstein: show gateway auth status' })
    create('EinsteinChat', function(opts)
        with_prompt(opts.args, 'Einstein chat: ', function(text)
            if text ~= nil then
                run_flow('chat', text)
            end
        end)
    end, { desc = 'Einstein: chat with the gateway', nargs = '*' })
    create('EinsteinExplain', function(opts)
        local range = opts.range == 2 and opts.line1 or nil
        local range_last = opts.range == 2 and opts.line2 or nil
        local context = buffer_context(0, range, range_last)
        run_flow('explain', 'Explain this code.', context, 'Code (' .. vim.bo.filetype .. ')')
    end, { desc = 'Einstein: explain the current buffer or selection', range = true })
    create('EinsteinGenerate', function(opts)
        with_prompt(opts.args, 'Einstein generate: ', function(text)
            if text == nil then
                return
            end
            local range = opts.range == 2 and opts.line1 or nil
            local range_last = opts.range == 2 and opts.line2 or nil
            local context = nil
            if range ~= nil then
                context = buffer_context(0, range, range_last)
            end
            run_flow('generate', text, context, 'Reference code (' .. vim.bo.filetype .. ')')
        end)
    end, { desc = 'Einstein: generate code from a prompt', nargs = '*', range = true })
    create('EinsteinGenerateTests', function(opts)
        local filetype = vim.bo.filetype
        local flow = nil
        if filetype == 'apex' or filetype == 'cls' then
            flow = 'generate_tests_apex'
        elseif filetype == 'javascript' or filetype == 'html' then
            flow = 'generate_tests_lwc'
        end
        if flow == nil then
            ui.notify_error({
                code = 'unsupported_filetype',
                message = 'test generation supports Apex and LWC buffers, not ' .. filetype,
            })
            return
        end
        local range = opts.range == 2 and opts.line1 or nil
        local range_last = opts.range == 2 and opts.line2 or nil
        local context = buffer_context(0, range, range_last)
        run_flow(flow, 'Generate tests for this code.', context, 'Code under test (' .. filetype .. ')')
    end, { desc = 'Einstein: generate tests for the current buffer', range = true })
    create('EinsteinModels', command_models, { desc = 'Einstein: list gateway model identifiers' })
end

---Plugin entry point. Safe to call more than once; later calls replace
---the active configuration.
---@param opts? table Setup options, see EinsteinConfig.
---@return boolean ok
function M.setup(opts)
    local resolved, err = config.resolve(opts)
    if resolved == nil then
        vim.notify('einstein: ' .. (err or 'invalid configuration'), vim.log.levels.ERROR)
        return false
    end
    active_config = resolved
    auth.clear_cache()
    register_commands()
    return true
end

---Public auth view for scripts and health checks (never the token).
---@param callback fun(view: table)
function M.auth_status(callback)
    auth.status(cfg(), callback)
end

---Drop the cached Salesforce session.
function M.reset_auth()
    auth.clear_cache()
end

return M
