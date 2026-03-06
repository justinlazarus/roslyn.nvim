local progress = require('roslyn.progress')

describe('progress.on_progress', function()
  it('ignores nil value', function()
    -- Should not error
    progress.on_progress('tok1', nil, 'roslyn')
  end)

  it('ignores non-table value', function()
    progress.on_progress('tok2', 'string', 'roslyn')
  end)

  it('ignores table without kind', function()
    progress.on_progress('tok3', { title = 'test' }, 'roslyn')
  end)

  it('accepts begin/end lifecycle', function()
    -- These exercise the code paths; visual output is not testable in headless
    progress.on_progress('tok4', { kind = 'begin', title = 'Loading' }, 'roslyn')
    progress.on_progress('tok4', { kind = 'report', message = 'halfway', percentage = 50 }, 'roslyn')
    progress.on_progress('tok4', { kind = 'end', message = 'done' }, 'roslyn')
  end)
end)

describe('progress.begin/finish', function()
  it('wraps on_progress with begin kind', function()
    -- Should not error
    progress.begin('custom_token', 'Loading MyApp.sln')
  end)

  it('wraps on_progress with end kind', function()
    progress.finish('custom_token', 'MyApp.sln')
  end)
end)
