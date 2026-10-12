-- einstein.nvim: configuration defaults and validation.
-- SPDX-License-Identifier: BSD-3-Clause
--
-- The gateway base URLs and native model identifiers in this file are
-- client constants extracted from the shipped Agentforce Vibes extension
-- bundle (Open VSX salesforcedx-einstein-gpt 4.35.0, dist/extension.js):
-- the environment-to-host switch and the model catalog table. Everything
-- else here is this plugin's own configuration surface.

local M = {}

---@class EinsteinConfig
---@field base_url string Gateway base URL, no trailing slash.
---@field environment string Environment key the base URL was resolved from.
---@field feature_id? string Optional x-client-feature-id header value.
---@field max_tokens integer Default max_tokens generation setting.
---@field model string Native gateway model identifier.
---@field sf_executable string Salesforce CLI executable name or path.
---@field sf_target_org? string Optional sf --target-org alias or username.
---@field temperature number Default temperature generation setting.
---@field timeout_ms integer HTTP timeout budget in milliseconds.

local BASE_URLS = {
    dev = 'https://dev.api.salesforce.com/ai/gpt/v1',
    perf = 'https://perf.api.salesforce.com/ai/gpt/v1',
    prod = 'https://api.salesforce.com/ai/gpt/v1',
    stage = 'https://stage.api.salesforce.com/ai/gpt/v1',
    test = 'https://test.api.salesforce.com/ai/gpt/v1',
}

local MAX_TOKENS_LIMIT = 32768
local TIMEOUT_MS_LIMIT = 600000
local TIMEOUT_MS_MINIMUM = 1000

---Native gateway model identifiers from the extension's model catalog.
---@type table<string, string>
M.MODELS = {
    claude_opus_4_5 = 'sfdc_ai__DefaultBedrockAnthropicClaude45Opus',
    claude_opus_4_6 = 'sfdc_ai__DefaultBedrockAnthropicClaude46Opus',
    claude_opus_4_7 = 'sfdc_ai__DefaultBedrockAnthropicClaude47Opus',
    claude_opus_4_8 = 'sfdc_ai__DefaultBedrockAnthropicClaude48Opus',
    claude_sonnet_4_6 = 'sfdc_ai__DefaultBedrockAnthropicClaude46Sonnet',
    gpt_5 = 'sfdc_ai__DefaultGPT5',
    gpt_5_1 = 'sfdc_ai__DefaultGPT51',
    gpt_5_4 = 'sfdc_ai__DefaultGPT54',
}

---The extension's default model (its catalog default entry).
M.DEFAULT_MODEL = M.MODELS.claude_sonnet_4_6

---@return EinsteinConfig
local function defaults()
    return {
        base_url = BASE_URLS.prod,
        environment = 'prod',
        max_tokens = 4096,
        model = M.DEFAULT_MODEL,
        sf_executable = 'sf',
        temperature = 0.2,
        timeout_ms = 120000,
    }
end

---Merge user options over the defaults and validate every field.
---@param opts? table User options, same field names as EinsteinConfig.
---@return EinsteinConfig? config, string? error
function M.resolve(opts)
    if opts ~= nil and type(opts) ~= 'table' then
        return nil, 'einstein: setup options must be a table'
    end
    local cfg = defaults()
    for key, value in pairs(opts or {}) do
        cfg[key] = value
    end
    if cfg.environment ~= nil then
        local url = BASE_URLS[cfg.environment]
        if url == nil then
            return nil, 'einstein: unknown environment: ' .. tostring(cfg.environment)
        end
        cfg.base_url = url
    end
    if type(cfg.base_url) ~= 'string' or cfg.base_url:sub(1, 8) ~= 'https://' then
        return nil, 'einstein: base_url must be an https URL'
    end
    cfg.base_url = cfg.base_url:gsub('/+$', '')
    if type(cfg.model) ~= 'string' or cfg.model == '' then
        return nil, 'einstein: model must be a non-empty string'
    end
    if type(cfg.max_tokens) ~= 'number' or cfg.max_tokens < 1 or cfg.max_tokens > MAX_TOKENS_LIMIT then
        return nil, 'einstein: max_tokens must be between 1 and ' .. MAX_TOKENS_LIMIT
    end
    if type(cfg.temperature) ~= 'number' or cfg.temperature < 0 or cfg.temperature > 2 then
        return nil, 'einstein: temperature must be between 0 and 2'
    end
    if type(cfg.timeout_ms) ~= 'number' or cfg.timeout_ms < TIMEOUT_MS_MINIMUM or cfg.timeout_ms > TIMEOUT_MS_LIMIT then
        return nil, 'einstein: timeout_ms must be between ' .. TIMEOUT_MS_MINIMUM .. ' and ' .. TIMEOUT_MS_LIMIT
    end
    if type(cfg.sf_executable) ~= 'string' or cfg.sf_executable == '' then
        return nil, 'einstein: sf_executable must be a non-empty string'
    end
    return cfg
end

return M
