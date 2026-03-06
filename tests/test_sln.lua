local sln = require('roslyn.sln')

local fixtures = vim.fn.getcwd() .. '/tests/fixtures'

describe('sln.parse_sln_projects', function()
  it('parses project paths from a .sln file', function()
    local projects = sln.parse_sln_projects(fixtures .. '/MyApp.sln')
    eq(2, #projects)
    ok(projects[1]:match('src/MyApp/MyApp%.csproj$'), 'first project should be MyApp.csproj')
    ok(projects[2]:match('tests/MyApp%.Tests/MyApp%.Tests%.csproj$'), 'second project should be MyApp.Tests.csproj')
  end)

  it('normalizes backslashes to forward slashes', function()
    local projects = sln.parse_sln_projects(fixtures .. '/MyApp.sln')
    for _, p in ipairs(projects) do
      eq(nil, p:find('\\'), 'path should not contain backslashes: ' .. p)
    end
  end)

  it('returns empty table for sln with no projects', function()
    local projects = sln.parse_sln_projects(fixtures .. '/Empty.sln')
    eq(0, #projects)
  end)

  it('returns empty table for nonexistent file', function()
    local projects = sln.parse_sln_projects(fixtures .. '/DoesNotExist.sln')
    eq(0, #projects)
  end)
end)

describe('sln.parse_slnx_projects', function()
  it('parses project paths from a .slnx file', function()
    local projects = sln.parse_slnx_projects(fixtures .. '/MyApp.slnx')
    eq(2, #projects)
    ok(projects[1]:match('src/MyApp/MyApp%.csproj$'))
    ok(projects[2]:match('tests/MyApp%.Tests/MyApp%.Tests%.csproj$'))
  end)
end)

describe('sln.parse_slnf_projects', function()
  it('parses project paths from a .slnf file', function()
    local projects = sln.parse_slnf_projects(fixtures .. '/MyApp.slnf')
    eq(1, #projects)
    ok(projects[1]:match('src/MyApp/MyApp%.csproj$'))
  end)

  it('normalizes backslashes', function()
    local projects = sln.parse_slnf_projects(fixtures .. '/MyApp.slnf')
    for _, p in ipairs(projects) do
      eq(nil, p:find('\\'), 'path should not contain backslashes: ' .. p)
    end
  end)

  it('returns empty table for invalid JSON', function()
    -- Empty.sln is not valid JSON
    local projects = sln.parse_slnf_projects(fixtures .. '/Empty.sln')
    eq(0, #projects)
  end)
end)

describe('sln.find_solutions', function()
  it('finds .sln files searching upward', function()
    local solutions = sln.find_solutions(fixtures)
    ok(#solutions > 0, 'should find at least one solution')
    local has_sln = false
    for _, s in ipairs(solutions) do
      if s:match('%.sln$') then has_sln = true end
    end
    ok(has_sln, 'should find a .sln file')
  end)

  it('does not match partial filenames like .slnx as .sln', function()
    -- The $ anchor fix ensures *.sln does not match *.slnx or *.slnf
    local solutions = sln.find_solutions(fixtures)
    for _, s in ipairs(solutions) do
      -- Each file should match exactly one of the patterns
      local ext = vim.fn.fnamemodify(s, ':e')
      ok(ext == 'sln' or ext == 'slnx' or ext == 'slnf',
        'should only match solution files, got: ' .. s)
    end
  end)
end)

describe('sln.find_solutions_broad', function()
  it('finds solutions recursively from a root', function()
    local solutions = sln.find_solutions_broad(fixtures)
    ok(#solutions > 0, 'should find solutions in fixtures')
  end)

  it('skips ignored directories', function()
    -- Create a temp dir with an ignored name
    local ignore_dir = fixtures .. '/node_modules'
    vim.fn.mkdir(ignore_dir, 'p')
    local fake_sln = ignore_dir .. '/Bad.sln'
    vim.fn.writefile({ 'fake' }, fake_sln)

    local solutions = sln.find_solutions_broad(fixtures)
    for _, s in ipairs(solutions) do
      eq(nil, s:find('node_modules'), 'should skip node_modules: ' .. s)
    end

    -- Clean up
    vim.fn.delete(fake_sln)
    vim.fn.delete(ignore_dir, 'd')
  end)
end)

describe('sln.find_projects', function()
  it('returns empty when no .csproj exists', function()
    -- fixtures dir has no .csproj files
    local projects = sln.find_projects(fixtures)
    eq(0, #projects)
  end)
end)

describe('sln.resolve', function()
  it('finds solution and returns root dir', function()
    local root, target, target_type = sln.resolve(fixtures .. '/MyApp.sln')
    ok(root ~= nil, 'should find a root dir')
    ok(target ~= nil, 'should find a target')
    eq('solution', target_type)
  end)

  it('returns nil for a path with no solution or project', function()
    local root, target, target_type = sln.resolve('/tmp')
    eq(nil, root)
    eq(nil, target)
    eq(nil, target_type)
  end)
end)
