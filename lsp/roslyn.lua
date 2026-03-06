local sln = require('roslyn.sln')
local handlers = require('roslyn.handlers')

local iswin = vim.uv.os_uname().sysname:find('Windows') ~= nil

local function get_cmd()
  local bin = iswin and 'roslyn.cmd' or 'roslyn'
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath('data'), 'mason', 'bin', bin)

  local exe
  if vim.fn.executable(mason_bin) == 1 then
    exe = mason_bin
  elseif vim.fn.executable(bin) == 1 then
    exe = bin
  elseif vim.fn.executable('Microsoft.CodeAnalysis.LanguageServer') == 1 then
    exe = 'Microsoft.CodeAnalysis.LanguageServer'
  else
    vim.notify(
      'roslyn.nvim: Roslyn language server not found.\n'
        .. 'Install via Mason (Crashdummyy registry) or ensure "roslyn" is on your PATH.',
      vim.log.levels.WARN
    )
    return nil
  end

  local log_dir = vim.fs.joinpath(vim.fn.stdpath('log'), 'roslyn')
  vim.fn.mkdir(log_dir, 'p')

  return { exe, '--logLevel=Information', '--extensionLogDirectory=' .. log_dir, '--stdio' }
end

return {
  cmd = get_cmd(),
  filetypes = { 'cs' },
  cmd_env = {
    Configuration = vim.env.Configuration or 'Debug',
    TMPDIR = vim.env.TMPDIR and vim.fn.resolve(vim.env.TMPDIR) or nil,
  },

  root_dir = function(bufnr, on_dir)
    local bufpath = vim.api.nvim_buf_get_name(bufnr)
    if bufpath == '' then return end

    local config = require('roslyn').config
    local root, target, target_type = sln.resolve(bufpath, { broad_search = config.broad_search })

    if root then
      -- Store the target for on_init to use
      vim.g.roslyn_lsp_target = target
      vim.g.roslyn_lsp_target_type = target_type
      -- For fast_init: find nearest .csproj to open first when target is a solution
      if config.fast_init and target_type == 'solution' then
        local projects = sln.find_projects(vim.fs.dirname(bufpath))
        if projects and #projects > 0 then
          vim.g.roslyn_lsp_fast_init_project = projects[1]
        end
      end
      on_dir(root)
    end
  end,

  capabilities = {
    textDocument = {
      callHierarchy = { dynamicRegistration = true },
      definition = { dynamicRegistration = true, linkSupport = true },
      references = { dynamicRegistration = true },
      implementation = { dynamicRegistration = true },
      typeDefinition = { dynamicRegistration = true, linkSupport = true },
      codeAction = {
        dynamicRegistration = true,
        codeActionLiteralSupport = {
          codeActionKind = {
            valueSet = {
              '',
              'quickfix',
              'refactor',
              'refactor.extract',
              'refactor.inline',
              'refactor.rewrite',
              'source',
              'source.organizeImports',
              'source.fixAll',
            },
          },
        },
        resolveSupport = { properties = { 'edit' } },
      },
      completion = {
        completionItem = {
          snippetSupport = true,
          resolveSupport = { properties = { 'documentation', 'detail', 'additionalTextEdits' } },
        },
      },
      diagnostic = { dynamicRegistration = true },
      inlayHint = { dynamicRegistration = true },
      semanticTokens = {
        dynamicRegistration = true,
        requests = { full = { delta = true }, range = true },
        tokenTypes = {
          'namespace', 'type', 'class', 'enum', 'interface', 'struct',
          'typeParameter', 'parameter', 'variable', 'property', 'enumMember',
          'event', 'function', 'method', 'macro', 'keyword', 'modifier',
          'comment', 'string', 'number', 'regexp', 'operator', 'decorator',
        },
        tokenModifiers = {
          'declaration', 'definition', 'readonly', 'static', 'deprecated',
          'abstract', 'async', 'modification', 'documentation', 'defaultLibrary',
        },
        formats = { 'relative' },
        multilineTokenSupport = false,
      },
    },
    workspace = {
      didChangeWatchedFiles = { dynamicRegistration = false },
      workspaceFolders = true,
    },
  },

  on_init = function(client)
    -- Transform clean settings keys into Roslyn's csharp| wire format
    local transformed
    if next(client.settings) then
      transformed = {}
      for key, val in pairs(client.settings) do
        if not key:find('|') then
          transformed['csharp|' .. key] = val
        else
          transformed[key] = val
        end
      end
      client.settings = transformed
    end

    local config = require('roslyn').config

    -- Use locked target if configured
    if config.lock_target and vim.g.roslyn_lsp_locked_target then
      vim.g.roslyn_lsp_target = vim.g.roslyn_lsp_locked_target
      vim.g.roslyn_lsp_target_type = vim.g.roslyn_lsp_locked_target_type
    end

    local target = vim.g.roslyn_lsp_target
    local target_type = vim.g.roslyn_lsp_target_type

    -- Fast init: open nearest project first, then upgrade to solution after init
    local fast_project = vim.g.roslyn_lsp_fast_init_project
    vim.g.roslyn_lsp_fast_init_project = nil

    local deferred_solution = nil
    if config.fast_init and fast_project and target_type == 'solution' then
      deferred_solution = target
      handlers.register(client, fast_project, {
        deferred_solution = target,
        settings = transformed,
      })
    else
      handlers.register(client, target)
    end

    if not target then return end

    -- Lock target for future sessions if configured
    if config.lock_target then
      vim.g.roslyn_lsp_locked_target = target
      vim.g.roslyn_lsp_locked_target_type = target_type
    end

    -- Send the solution/project open notification
    if deferred_solution then
      -- Fast init: open just the project first
      client:notify('project/open', { projects = { vim.uri_from_fname(fast_project) } })
    elseif target_type == 'solution' then
      client:notify('solution/open', { solution = vim.uri_from_fname(target) })
    elseif target_type == 'project' then
      client:notify('project/open', { projects = { vim.uri_from_fname(target) } })
    end

    -- Send settings after solution/project open so Roslyn can apply them
    if transformed then
      client:notify('workspace/didChangeConfiguration', { settings = transformed })
    end
  end,

  on_attach = function(client, bufnr)
    vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynAttach', data = { client_id = client.id, bufnr = bufnr } })
  end,
}
