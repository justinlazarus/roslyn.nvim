--- nvim.roslyn — a native Neovim LSP wrapper for the Roslyn C# language server.
local M = {}

M.config = {
  filewatching = 'auto', -- "auto" | "off"
  broad_search = false, -- recursively search for solution files
  lock_target = false, -- always reuse previously selected target
  fast_init = false, -- load nearest project first, then upgrade to full solution
}

--- Setup the plugin: register commands and autocmds.
---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  require('roslyn.commands').setup()
  require('roslyn.progress').setup()
  vim.lsp.enable('roslyn')
end

return M
