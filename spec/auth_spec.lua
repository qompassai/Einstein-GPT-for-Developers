-- Busted specs for einstein.auth pure helpers.
package.path = 'lua/?.lua;lua/?/init.lua;' .. package.path

local auth = require('einstein.auth')

describe('einstein.auth.from_sf_json', function()
    it('builds a session from a complete sf result', function()
        local session, err = auth.from_sf_json({
            result = {
                accessToken = 'token-value',
                id = '00D000000000001',
                instanceUrl = 'https://example.my.salesforce.com',
                username = 'dev@example.com',
            },
        })
        assert.is_nil(err)
        assert.is_not_nil(session)
        assert.are.equal('token-value', session.access_token)
        assert.are.equal('00D000000000001', session.org_id)
        assert.are.equal('sf', session.source)
    end)

    it('fails closed when the access token is missing', function()
        local session, err = auth.from_sf_json({ result = { username = 'dev@example.com' } })
        assert.is_nil(session)
        assert.is_string(err)
    end)

    it('fails closed when the result object is missing', function()
        local session = auth.from_sf_json({})
        assert.is_nil(session)
    end)

    it('fails closed on a non-table document', function()
        local session = auth.from_sf_json('not a table')
        assert.is_nil(session)
    end)
end)

describe('einstein.auth.session_from_env', function()
    it('builds a session from an explicit token', function()
        local session = auth.session_from_env({ tenant_id = '00D1', token = 'abc' })
        assert.is_not_nil(session)
        assert.are.equal('env', session.source)
        assert.are.equal('00D1', session.org_id)
    end)

    it('returns nil without a token', function()
        assert.is_nil(auth.session_from_env({}))
        assert.is_nil(auth.session_from_env({ token = '' }))
    end)
end)
