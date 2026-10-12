-- einstein.nvim plugin entry point.
-- SPDX-License-Identifier: BSD-3-Clause
if vim.g.loaded_einstein then
    return
end
vim.g.loaded_einstein = 1
if vim.fn.has('nvim-0.10') == 0 then
    vim.notify('einstein.nvim requires Neovim 0.10 or newer', vim.log.levels.ERROR)
    return
end
require('einstein').setup(vim.g.einstein or {})
