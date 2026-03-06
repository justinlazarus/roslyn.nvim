--- Solution/project discovery and parsing for Roslyn LSP.
local M = {}

local sln_patterns = { '*.sln', '*.slnx', '*.slnf' }
local ignore_dirs = { 'obj', 'bin', '.git', 'node_modules' }

--- Find solution files by searching upward from `start_path`.
---@param start_path string
---@return string[]
function M.find_solutions(start_path)
  local results = {}
  for _, pattern in ipairs(sln_patterns) do
    local lua_pat = pattern:gsub('%.', '%%.'):gsub('%*', '.*') .. '$'
    local found = vim.fs.find(function(name)
      return name:match(lua_pat)
    end, { path = start_path, upward = true, type = 'file', limit = math.huge })
    vim.list_extend(results, found)
  end
  return results
end

--- Broad recursive search for solution files from `root`.
---@param root string
---@return string[]
function M.find_solutions_broad(root)
  local results = {}
  local function walk(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == 'directory' and not vim.tbl_contains(ignore_dirs, name) then
        walk(vim.fs.joinpath(dir, name))
      elseif typ == 'file' then
        for _, pat in ipairs(sln_patterns) do
          if name:match(pat:gsub('%.', '%%.'):gsub('%*', '.*') .. '$') then
            table.insert(results, vim.fs.joinpath(dir, name))
          end
        end
      end
    end
  end
  walk(root)
  return results
end

--- Find .csproj files by searching upward from `start_path`.
---@param start_path string
---@return string[]
function M.find_projects(start_path)
  return vim.fs.find(function(name)
    return name:match('%.csproj$')
  end, { path = start_path, upward = true, type = 'file', limit = math.huge })
end

--- Parse a .sln file and return project paths relative to the sln directory.
---@param sln_path string
---@return string[]
function M.parse_sln_projects(sln_path)
  local dir = vim.fs.dirname(sln_path)
  local projects = {}
  local ok, lines = pcall(vim.fn.readfile, sln_path)
  if not ok then return projects end
  for _, line in ipairs(lines) do
    -- Project("{guid}") = "Name", "path.csproj", "{guid}"
    local proj_path = line:match('Project%b()%s*=%s*"[^"]*"%s*,%s*"([^"]+%.csproj)"')
    if proj_path then
      -- Normalize path separators
      proj_path = proj_path:gsub('\\', '/')
      table.insert(projects, vim.fs.joinpath(dir, proj_path))
    end
  end
  return projects
end

--- Parse a .slnx file and return project paths.
---@param slnx_path string
---@return string[]
function M.parse_slnx_projects(slnx_path)
  local dir = vim.fs.dirname(slnx_path)
  local projects = {}
  local ok, lines = pcall(vim.fn.readfile, slnx_path)
  if not ok then return projects end
  local content = table.concat(lines, '\n')
  for path in content:gmatch('<Project%s+Path="([^"]+)"') do
    path = path:gsub('\\', '/')
    table.insert(projects, vim.fs.joinpath(dir, path))
  end
  return projects
end

--- Parse a .slnf (solution filter) file and return project paths.
---@param slnf_path string
---@return string[]
function M.parse_slnf_projects(slnf_path)
  local dir = vim.fs.dirname(slnf_path)
  local projects = {}
  local ok, lines = pcall(vim.fn.readfile, slnf_path)
  if not ok then return projects end
  local json_ok, data = pcall(vim.fn.json_decode, table.concat(lines, '\n'))
  if not json_ok or type(data) ~= 'table' then return projects end
  local solution = data.solution
  if solution and solution.projects then
    for _, p in ipairs(solution.projects) do
      p = p:gsub('\\', '/')
      table.insert(projects, vim.fs.joinpath(dir, p))
    end
  end
  return projects
end

--- Determine the root directory for the Roslyn LSP given a buffer path.
--- Returns (root_dir, target_path, target_type) where target_type is "solution" or "project".
---@param bufpath string
---@param opts? { broad_search?: boolean }
---@return string|nil root_dir
---@return string|nil target_path
---@return string|nil target_type "solution"|"project"
function M.resolve(bufpath, opts)
  opts = opts or {}
  local start = vim.fs.dirname(bufpath)

  -- Try solutions first
  local solutions = M.find_solutions(start)
  if opts.broad_search and #solutions == 0 then
    -- Walk up to find a plausible root then search broadly
    local git_root = vim.fs.find('.git', { path = start, upward = true, type = 'directory' })
    if git_root and #git_root > 0 then
      solutions = M.find_solutions_broad(vim.fs.dirname(git_root[1]))
    end
  end

  if #solutions > 0 then
    -- If single solution, use it directly
    if #solutions == 1 then
      return vim.fs.dirname(solutions[1]), solutions[1], 'solution'
    end
    -- Multiple solutions: try to pick the one containing the current file's project
    local csproj = M.find_projects(start)
    if csproj and #csproj > 0 then
      local proj = csproj[1]
      for _, sln in ipairs(solutions) do
        local ext = vim.fn.fnamemodify(sln, ':e')
        local parser = ext == 'sln' and M.parse_sln_projects
          or ext == 'slnx' and M.parse_slnx_projects
          or ext == 'slnf' and M.parse_slnf_projects
        if parser then
          local sln_projects = parser(sln)
          for _, sp in ipairs(sln_projects) do
            if vim.fs.normalize(sp) == vim.fs.normalize(proj) then
              return vim.fs.dirname(sln), sln, 'solution'
            end
          end
        end
      end
    end
    -- Fall back to the first (closest) solution
    return vim.fs.dirname(solutions[1]), solutions[1], 'solution'
  end

  -- No solutions found, try .csproj
  local projects = M.find_projects(start)
  if projects and #projects > 0 then
    return vim.fs.dirname(projects[1]), projects[1], 'project'
  end

  return nil, nil, nil
end

return M
