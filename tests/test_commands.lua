local commands = require('roslyn.commands')

describe('commands.subcommands', function()
  it('has all documented subcommands', function()
    local expected = {
      'info', 'target', 'restart', 'stop', 'restore', 'log',
      'incoming_calls', 'outgoing_calls', 'references',
      'implementation', 'type_definition', 'document_symbols',
      'workspace_symbols', 'organize_imports', 'fix_all',
      'open_sourcegen',
    }
    for _, name in ipairs(expected) do
      ok(commands.subcommands[name] ~= nil, 'missing subcommand: ' .. name)
      eq('function', type(commands.subcommands[name]), name .. ' should be a function')
    end
  end)

  it('has no undocumented subcommands', function()
    local known = {
      info = true, target = true, restart = true, stop = true,
      restore = true, log = true, incoming_calls = true,
      outgoing_calls = true, references = true, implementation = true,
      type_definition = true, document_symbols = true,
      workspace_symbols = true, organize_imports = true,
      fix_all = true, open_sourcegen = true,
    }
    for name, _ in pairs(commands.subcommands) do
      ok(known[name], 'undocumented subcommand: ' .. name)
    end
  end)
end)

describe('commands without active client', function()
  it('info handles no client gracefully', function()
    -- Should notify and not error (no client running)
    local notified = false
    local orig = vim.notify
    vim.notify = function(msg, level)
      if msg:find('no active client') then notified = true end
    end
    commands.subcommands.info()
    vim.notify = orig
    ok(notified, 'should notify about missing client')
  end)

  it('stop handles no client gracefully', function()
    local notified = false
    local orig = vim.notify
    vim.notify = function(msg, level)
      if msg:find('no active client') then notified = true end
    end
    commands.subcommands.stop()
    vim.notify = orig
    ok(notified, 'should notify about missing client')
  end)

  it('restore handles no client gracefully', function()
    local notified = false
    local orig = vim.notify
    vim.notify = function(msg, level)
      if msg:find('no active client') then notified = true end
    end
    commands.subcommands.restore()
    vim.notify = orig
    ok(notified, 'should notify about missing client')
  end)
end)
