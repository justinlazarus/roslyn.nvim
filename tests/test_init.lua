describe('roslyn.config', function()
  it('has sensible defaults', function()
    -- Fresh require to get defaults
    package.loaded['roslyn'] = nil
    local roslyn = require('roslyn')
    eq('auto', roslyn.config.filewatching)
    eq(false, roslyn.config.broad_search)
    eq(false, roslyn.config.lock_target)
    eq(false, roslyn.config.fast_init)
  end)

  it('merges user config with defaults', function()
    package.loaded['roslyn'] = nil
    local roslyn = require('roslyn')
    -- Simulate setup without enabling LSP (no server available in test)
    roslyn.config = vim.tbl_deep_extend('force', roslyn.config, {
      broad_search = true,
      filewatching = 'off',
    })
    eq(true, roslyn.config.broad_search)
    eq('off', roslyn.config.filewatching)
    eq(false, roslyn.config.lock_target) -- unchanged default
    eq(false, roslyn.config.fast_init) -- unchanged default
  end)
end)
