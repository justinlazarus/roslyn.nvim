--- Minimal test runner for Neovim headless testing.
local M = {}

local passed = 0
local failed = 0
local errors = {}

function M.describe(name, fn)
  print('  ' .. name)
  fn()
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('    PASS: ' .. name)
  else
    failed = failed + 1
    table.insert(errors, { name = name, err = err })
    print('    FAIL: ' .. name)
    print('          ' .. tostring(err))
  end
end

function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    local detail = string.format(
      '%s\n  expected: %s\n  actual:   %s',
      msg or '',
      vim.inspect(expected),
      vim.inspect(actual)
    )
    error(detail, 2)
  end
end

function M.neq(a, b, msg)
  if vim.deep_equal(a, b) then
    error((msg or '') .. '\n  values should not be equal: ' .. vim.inspect(a), 2)
  end
end

function M.ok(val, msg)
  if not val then
    error(msg or 'expected truthy value', 2)
  end
end

function M.run()
  print('')
  print('roslyn.nvim tests')
  print(string.rep('─', 40))

  -- Discover and run test files
  local test_dir = vim.fn.getcwd() .. '/tests'
  local test_files = vim.fn.glob(test_dir .. '/test_*.lua', false, true)
  table.sort(test_files)

  for _, file in ipairs(test_files) do
    local mod_name = file:match('tests/(test_.+)%.lua$')
    if mod_name then
      print('')
      print(mod_name)
      dofile(file)
    end
  end

  print('')
  print(string.rep('─', 40))
  print(string.format('Results: %d passed, %d failed', passed, failed))

  if #errors > 0 then
    print('')
    print('Failures:')
    for _, e in ipairs(errors) do
      print('  - ' .. e.name .. ': ' .. tostring(e.err))
    end
  end

  print('')
  vim.cmd('qa' .. (failed > 0 and '!' or ''))
  if failed > 0 then
    os.exit(1)
  end
end

-- Make helpers available globally for test files
_G.describe = M.describe
_G.it = M.it
_G.eq = M.eq
_G.neq = M.neq
_G.ok = M.ok

return M
