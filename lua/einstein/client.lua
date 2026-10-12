-- einstein.nvim: Einstein GPT gateway client.
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Wire format extracted from the shipped Agentforce Vibes extension
-- bundle (Open VSX salesforcedx-einstein-gpt 4.35.0, dist/extension.js):
--   POST {base_url}/chat/generations
--   Headers: Authorization: Bearer <org access token>,
--     Content-Type: application/json;charset=utf-8,
--     x-sfdc-app-context: EinsteinGPT,
--     x-sfdc-core-tenant-id: <org id>,
--     x-client-feature-id: <feature id> (only when configured)
--   Body: { model, messages = { { role, content }, ... },
--     generation_settings = { max_tokens, temperature, ... },
--     system_prompt_strategy = 'use_model_parameter' }
--   Response envelope: generation_details.generations[1].content
-- Transport is curl in argv form via vim.system. The bearer token is
-- passed through curl's stdin config channel (--config -) so it never
-- appears in the process argument list; the JSON body travels in a
-- temporary file that is deleted when the request completes.

local M = {}

local HTTP_STATUS_MARKER = '__EINSTEIN_HTTP_STATUS__:'
local ERROR_BODY_CHARS_MAX = 300

---@class EinsteinRequest
---@field body table JSON-encodable request body.
---@field headers string[] Header lines, without the Authorization header.
---@field url string Fully-qualified request URL.

---Assemble the request for a chat generation (pure, testable).
---@param cfg EinsteinConfig
---@param messages table[] Chat messages, { role = string, content = string }.
---@return EinsteinRequest
function M.build_request(cfg, messages)
    assert(type(cfg) == 'table', 'einstein.client.build_request: cfg must be a table')
    assert(type(messages) == 'table', 'einstein.client.build_request: messages must be a table')
    local headers = {
        'Content-Type: application/json;charset=utf-8',
        'x-sfdc-app-context: EinsteinGPT',
    }
    if cfg.feature_id ~= nil and cfg.feature_id ~= '' then
        headers[#headers + 1] = 'x-client-feature-id: ' .. cfg.feature_id
    end
    return {
        body = {
            generation_settings = {
                max_tokens = cfg.max_tokens,
                temperature = cfg.temperature,
            },
            messages = messages,
            model = cfg.model,
            system_prompt_strategy = 'use_model_parameter',
        },
        headers = headers,
        url = cfg.base_url .. '/chat/generations',
    }
end

---Extract the generated text from a decoded response (pure, testable).
---@param decoded table Decoded response JSON.
---@return string? text, string? error
function M.extract_text(decoded)
    if type(decoded) ~= 'table' then
        return nil, 'response was not a JSON object'
    end
    local details = decoded.generation_details
    local generations = type(details) == 'table' and details.generations or nil
    local first = type(generations) == 'table' and generations[1] or nil
    if type(first) == 'table' and type(first.content) == 'string' then
        return first.content
    end
    return nil, 'response did not contain generation_details.generations[1].content'
end

---Escape a value for a curl config line (double-quoted string).
---@param value string
---@return string
local function curl_config_quote(value)
    return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

---Split curl stdout into body and trailing HTTP status marker.
---@param stdout string
---@return string body, number? status
local function split_status(stdout)
    local body, status = stdout:match('^(.*)\n' .. HTTP_STATUS_MARKER .. '(%d+)%s*$')
    if body == nil then
        return stdout, nil
    end
    return body, tonumber(status)
end

---Send one chat generation and deliver the text via callback.
---@param cfg EinsteinConfig
---@param session EinsteinSession
---@param messages table[]
---@param callback fun(text?: string, err?: EinsteinError)
function M.chat(cfg, session, messages, callback)
    assert(type(session) == 'table', 'einstein.client.chat: session must be a table')
    assert(type(callback) == 'function', 'einstein.client.chat: callback must be a function')
    local request = M.build_request(cfg, messages)
    local body_path = vim.fn.tempname() .. '.json'
    vim.fn.writefile({ vim.json.encode(request.body) }, body_path)
    local config_lines = {
        'header = ' .. curl_config_quote('Authorization: Bearer ' .. session.access_token),
    }
    if session.org_id ~= nil and session.org_id ~= '' then
        config_lines[#config_lines + 1] = 'header = ' .. curl_config_quote('x-sfdc-core-tenant-id: ' .. session.org_id)
    end
    for _, header in ipairs(request.headers) do
        config_lines[#config_lines + 1] = 'header = ' .. curl_config_quote(header)
    end
    local timeout_s = math.ceil(cfg.timeout_ms / 1000)
    local argv = {
        'curl',
        '-sS',
        '--config',
        '-',
        '--max-time',
        tostring(timeout_s),
        '--data-binary',
        '@' .. body_path,
        '--write-out',
        '\n' .. HTTP_STATUS_MARKER .. '%{http_code}',
        request.url,
    }
    local ok, system_err = pcall(
        vim.system,
        argv,
        { stdin = table.concat(config_lines, '\n'), text = true },
        function(obj)
            vim.schedule(function()
                vim.fn.delete(body_path)
                if obj.code ~= 0 then
                    callback(nil, { code = 'network_error', message = vim.trim(obj.stderr or 'curl failed') })
                    return
                end
                local body, status = split_status(obj.stdout or '')
                if status ~= nil and status >= 400 then
                    callback(nil, {
                        code = 'http_error',
                        message = 'gateway returned HTTP ' .. status .. ': ' .. body:sub(1, ERROR_BODY_CHARS_MAX),
                        status = status,
                    })
                    return
                end
                local decode_ok, decoded = pcall(vim.json.decode, body)
                if not decode_ok or type(decoded) ~= 'table' then
                    callback(nil, { code = 'unexpected_response', message = 'gateway response was not JSON' })
                    return
                end
                local text, err = M.extract_text(decoded)
                if text == nil then
                    callback(nil, { code = 'unexpected_response', message = err or 'empty generation' })
                    return
                end
                callback(text)
            end)
        end
    )
    if not ok then
        vim.fn.delete(body_path)
        callback(nil, { code = 'network_error', message = 'could not start curl: ' .. tostring(system_err) })
    end
end

return M
