-- einstein.nvim: result display and error presentation.
-- SPDX-License-Identifier: BSD-3-Clause

local M = {}

local RESULT_BUFFER_NAME = 'einstein://result'
local RESULT_LINES_MAX = 5000

---Show text in the shared result split, creating it on first use.
---@param title string Heading line shown above the result.
---@param text string Result body, Markdown by convention.
function M.show_result(title, text)
    local lines = {}
    lines[#lines + 1] = '# ' .. title
    lines[#lines + 1] = ''
    local body_lines = vim.split(text, '\n', { plain = true })
    for index, line in ipairs(body_lines) do
        if index > RESULT_LINES_MAX then
            lines[#lines + 1] = '... [result truncated]'
            break
        end
        lines[#lines + 1] = line
    end
    local bufnr = vim.fn.bufnr(RESULT_BUFFER_NAME)
    if bufnr < 0 then
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, RESULT_BUFFER_NAME)
    end
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'hide'
    vim.bo[bufnr].filetype = 'markdown'
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    local win = vim.fn.bufwinid(bufnr)
    if win < 0 then
        vim.cmd('botright split')
        vim.api.nvim_win_set_buf(0, bufnr)
    end
end

---Present a structured error from auth or the client.
---@param err EinsteinError
function M.notify_error(err)
    local message = 'einstein: ' .. (err.message or 'unknown error')
    if err.code ~= nil then
        message = message .. ' [' .. err.code .. ']'
    end
    vim.notify(message, vim.log.levels.ERROR)
end

---Ask for a prompt string, then invoke the callback with it.
---@param label string Prompt shown to the user.
---@param callback fun(text?: string)
function M.input_prompt(label, callback)
    vim.ui.input({ prompt = label }, function(text)
        if text == nil or vim.trim(text) == '' then
            callback(nil)
            return
        end
        callback(text)
    end)
end

return M
