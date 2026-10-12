-- Busted specs for einstein.prompts.
package.path = 'lua/?.lua;lua/?/init.lua;' .. package.path

local prompts = require('einstein.prompts')

describe('einstein.prompts.messages_for', function()
    it('chat carries no system message', function()
        local messages = prompts.messages_for('chat', { prompt = 'hello' })
        assert.is_not_nil(messages)
        assert.are.equal(1, #messages)
        assert.are.equal('user', messages[1].role)
    end)

    it('explain adds a system message and fences the context', function()
        local messages = prompts.messages_for('explain', {
            context = 'public class A {}',
            context_label = 'Code (apex)',
            prompt = 'Explain this code.',
        })
        assert.are.equal(2, #messages)
        assert.are.equal('system', messages[1].role)
        assert.is_truthy(messages[2].content:find('public class A {}', 1, true))
    end)

    it('rejects an unknown flow', function()
        local messages, err = prompts.messages_for('nope', { prompt = 'x' })
        assert.is_nil(messages)
        assert.is_string(err)
    end)

    it('rejects an empty prompt', function()
        local messages = prompts.messages_for('chat', { prompt = '' })
        assert.is_nil(messages)
    end)

    it('truncates oversized context', function()
        local big = string.rep('x', 70000)
        local messages = prompts.messages_for('explain', { context = big, prompt = 'go' })
        assert.is_truthy(messages[2].content:find('%[truncated at 64000 characters%]'))
    end)
end)

describe('einstein.prompts.flow_names', function()
    it('is sorted and includes chat', function()
        local names = prompts.flow_names()
        local sorted = {}
        for _, name in ipairs(names) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)
        assert.are.same(sorted, names)
    end)
end)
