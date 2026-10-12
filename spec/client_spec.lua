-- Busted specs for einstein.client pure helpers.
package.path = 'lua/?.lua;lua/?/init.lua;' .. package.path

local client = require('einstein.client')
local config = require('einstein.config')

describe('einstein.client.build_request', function()
    it('targets the chat generations endpoint with the gateway contract', function()
        local cfg = config.resolve(nil)
        local request = client.build_request(cfg, { { content = 'hi', role = 'user' } })
        assert.are.equal('https://api.salesforce.com/ai/gpt/v1/chat/generations', request.url)
        assert.are.equal(config.DEFAULT_MODEL, request.body.model)
        assert.are.equal('use_model_parameter', request.body.system_prompt_strategy)
        assert.are.equal(4096, request.body.generation_settings.max_tokens)
        local joined = table.concat(request.headers, '\n')
        assert.is_truthy(joined:find('x%-sfdc%-app%-context: EinsteinGPT'))
        assert.is_falsy(joined:find('Authorization'))
    end)

    it('omits the tenant and feature headers at build time', function()
        local cfg = config.resolve(nil)
        local request = client.build_request(cfg, {})
        local joined = table.concat(request.headers, '\n')
        assert.is_falsy(joined:find('x%-sfdc%-core%-tenant%-id'))
        assert.is_falsy(joined:find('x%-client%-feature%-id'))
    end)
end)

describe('einstein.client.extract_text', function()
    it('reads generation_details.generations[1].content', function()
        local text, err = client.extract_text({
            generation_details = { generations = { { content = 'generated!' } } },
        })
        assert.is_nil(err)
        assert.are.equal('generated!', text)
    end)

    it('fails closed on an unexpected envelope', function()
        local text, err = client.extract_text({ generations = {} })
        assert.is_nil(text)
        assert.is_string(err)
    end)

    it('fails closed on a non-table response', function()
        local text = client.extract_text('nope')
        assert.is_nil(text)
    end)
end)
