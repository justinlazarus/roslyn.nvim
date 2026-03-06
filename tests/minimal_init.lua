-- Minimal init for running tests in headless Neovim.
-- Usage: nvim --headless -u tests/minimal_init.lua -c "lua require('tests.runner').run()"
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
