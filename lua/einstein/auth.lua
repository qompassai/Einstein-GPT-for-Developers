-- einstein.nvim: Salesforce session resolution.
-- SPDX-License-Identifier: BSD-3-Clause
--
-- The extension obtains its gateway bearer token from the authorized
-- org session held by the Salesforce core tooling. This module resolves
-- the same session from outside VS Code, in priority order:
--   1. Environment: EINSTEIN_SF_ACCESS_TOKEN (plus optional
--      EINSTEIN_SF_TENANT_ID and EINSTEIN_SF_INSTANCE_URL).
--   2. The Salesforce CLI: `sf org display --json`, whose result carries
--      accessToken, instanceUrl, id (the org id, sent to the gateway as
--      x-sfdc-core-tenant-id), and username.
-- Resolution fails closed: when neither source yields a token, callers
-- receive a structured { code = 'not_authenticated' } error. The token
-- itself is never logged, notified, or written to disk by this module.

local M = {}

---@class EinsteinSession
---@field access_token string Bearer token. Never log or display this value.
---@field instance_url string Org instance URL, informational only.
---@field org_id string Org id, sent as the x-sfdc-core-tenant-id header.
---@field source string Resolution source: 'env' or 'sf'.
---@field username string Org username, informational only.

---@class EinsteinError
---@field code string Machine-readable error code.
---@field message string Human-readable explanation.
---@field status? number HTTP status, present for http_error results.

---@type EinsteinSession?
local cached_session = nil

---Build the canonical fail-closed error table.
---@param message string
---@return EinsteinError
local function not_authenticated(message)
    return { code = 'not_authenticated', message = message }
end

---Build a session from explicit environment values (pure, testable).
---@param env { tenant_id?: string, token?: string, instance_url?: string }
---@return EinsteinSession?
function M.session_from_env(env)
    if type(env) ~= 'table' or type(env.token) ~= 'string' or env.token == '' then
        return nil
    end
    ---@type EinsteinSession
    local session = {
        access_token = env.token,
        instance_url = env.instance_url or '',
        org_id = env.tenant_id or '',
        source = 'env',
        username = '',
    }
    return session
end

---Build a session from decoded `sf org display --json` output (pure).
---@param decoded table Decoded JSON document.
---@return EinsteinSession? session, string? error
function M.from_sf_json(decoded)
    if type(decoded) ~= 'table' or type(decoded.result) ~= 'table' then
        return nil, 'sf org display output has no result object'
    end
    local result = decoded.result
    if type(result.accessToken) ~= 'string' or result.accessToken == '' then
        return nil, 'sf org display result is missing accessToken'
    end
    return {
        access_token = result.accessToken,
        instance_url = result.instanceUrl or '',
        org_id = result.id or '',
        source = 'sf',
        username = result.username or '',
    }
end

---Drop the cached session so the next resolve re-reads the sources.
function M.clear_cache()
    cached_session = nil
end

---Resolve a session asynchronously; the callback fires exactly once.
---@param cfg EinsteinConfig
---@param callback fun(session?: EinsteinSession, err?: EinsteinError)
function M.resolve(cfg, callback)
    assert(type(cfg) == 'table', 'einstein.auth.resolve: cfg must be a table')
    assert(type(callback) == 'function', 'einstein.auth.resolve: callback must be a function')
    if cached_session ~= nil then
        callback(cached_session)
        return
    end
    local env_session = M.session_from_env({
        instance_url = os.getenv('EINSTEIN_SF_INSTANCE_URL'),
        tenant_id = os.getenv('EINSTEIN_SF_TENANT_ID'),
        token = os.getenv('EINSTEIN_SF_ACCESS_TOKEN'),
    })
    if env_session ~= nil then
        cached_session = env_session
        callback(env_session)
        return
    end
    local argv = { cfg.sf_executable, 'org', 'display', '--json' }
    if cfg.sf_target_org ~= nil then
        argv[#argv + 1] = '--target-org'
        argv[#argv + 1] = cfg.sf_target_org
    end
    local ok, system_err = pcall(vim.system, argv, { text = true }, function(obj)
        vim.schedule(function()
            if obj.code ~= 0 then
                callback(nil, not_authenticated('no Salesforce org session: run `sf org login web` first'))
                return
            end
            local decode_ok, decoded = pcall(vim.json.decode, obj.stdout or '')
            if not decode_ok or type(decoded) ~= 'table' then
                callback(nil, not_authenticated('could not parse `sf org display --json` output'))
                return
            end
            local session, err = M.from_sf_json(decoded)
            if session == nil then
                callback(nil, not_authenticated(err or 'sf session is incomplete'))
                return
            end
            cached_session = session
            callback(session)
        end)
    end)
    if not ok then
        callback(nil, not_authenticated('Salesforce CLI is not runnable: ' .. tostring(system_err)))
    end
end

---Public, token-free view of the resolved session, for display.
---@param cfg EinsteinConfig
---@param callback fun(view: table)
function M.status(cfg, callback)
    M.resolve(cfg, function(session, err)
        if session == nil then
            callback({ authenticated = false, error = err })
            return
        end
        callback({
            authenticated = true,
            instance_url = session.instance_url,
            org_id = session.org_id,
            source = session.source,
            username = session.username,
        })
    end)
end

return M
