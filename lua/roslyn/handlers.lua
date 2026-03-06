--- Custom Roslyn LSP notification and request handlers.
local M = {}

local sourcegen = require('roslyn.sourcegen')
local progress = require('roslyn.progress')

--- Register all custom handlers on a client.
---@param client vim.lsp.Client
---@param target? string path to solution/project being loaded
---@param fast_init_opts? { deferred_solution: string, settings?: table }
function M.register(client, target, fast_init_opts)
  -- Start workspace loading progress indicator
  local label = 'Loading'
  if target then
    label = label .. ' ' .. vim.fn.fnamemodify(target, ':t')
  end
  progress.begin('roslyn_workspace', label)

  local function refresh_diagnostics()
    vim.schedule(function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'cs' then
          vim.lsp.buf_request(bufnr, 'textDocument/diagnostic', {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
          })
        end
      end
    end)
  end

  -- Project initialization complete
  if fast_init_opts and fast_init_opts.deferred_solution then
    -- Two-phase init: project first, then solution
    local phase = 'project'
    client.handlers['workspace/projectInitializationComplete'] = function()
      if phase == 'project' then
        phase = 'solution'
        local proj_name = target and vim.fn.fnamemodify(target, ':t') or 'project'
        progress.finish('roslyn_workspace', proj_name)
        vim.notify('Roslyn: project ready (' .. proj_name .. '), loading full solution...', vim.log.levels.INFO)
        vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynInitialized' })
        if next(client.settings) then
          client:notify('workspace/didChangeConfiguration', { settings = client.settings })
        end
        refresh_diagnostics()
        -- Now upgrade to full solution
        local sln_path = fast_init_opts.deferred_solution
        local sln_name = vim.fn.fnamemodify(sln_path, ':t')
        progress.begin('roslyn_workspace', 'Loading ' .. sln_name)
        client:notify('solution/open', { solution = vim.uri_from_fname(sln_path) })
      elseif phase == 'solution' then
        phase = 'done'
        local sln_name = vim.fn.fnamemodify(fast_init_opts.deferred_solution, ':t')
        progress.finish('roslyn_workspace', sln_name)
        vim.notify('Roslyn: full solution ready (' .. sln_name .. ')', vim.log.levels.INFO)
        vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynInitialized' })
        if next(client.settings) then
          client:notify('workspace/didChangeConfiguration', { settings = client.settings })
        end
        refresh_diagnostics()
      end
    end
  else
    client.handlers['workspace/projectInitializationComplete'] = function()
      local done_label = target and vim.fn.fnamemodify(target, ':t') or 'ready'
      progress.finish('roslyn_workspace', done_label)
      vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynInitialized' })
      if next(client.settings) then
        client:notify('workspace/didChangeConfiguration', { settings = client.settings })
      end
      refresh_diagnostics()
    end
  end

  -- Source-generated document refresh
  client.handlers['workspace/refreshSourceGeneratedDocument'] = function()
    sourcegen.refresh_all(client)
  end

  -- Project needs restore (server sends this as a request, expects a response)
  client.handlers['workspace/_roslyn_projectNeedsRestore'] = function(err, result, ctx)
    vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynRestoreNeeded', data = result })
    return vim.NIL
  end

  -- Handle nested code actions
  vim.lsp.commands['roslyn.client.nestedCodeAction'] = function(command, ctx)
    local actions = command.arguments and command.arguments[1]
    if not actions or #actions == 0 then return end
    vim.ui.select(actions, {
      prompt = 'Code Action',
      format_item = function(item) return item.title end,
    }, function(selected)
      if not selected then return end
      client:request('codeAction/resolve', selected, function(err, resolved)
        if err then
          vim.notify('Roslyn: ' .. tostring(err), vim.log.levels.ERROR)
          return
        end
        if resolved and resolved.edit then
          vim.lsp.util.apply_workspace_edit(resolved.edit, client.offset_encoding)
        end
      end)
    end)
  end

  -- Handle fix-all code actions
  vim.lsp.commands['roslyn.client.fixAllCodeAction'] = function(command, ctx)
    local action = command.arguments and command.arguments[1]
    if not action then return end
    local scopes = { 'document', 'project', 'solution' }
    vim.ui.select(scopes, { prompt = 'Fix All Scope' }, function(scope)
      if not scope then return end
      local params = vim.deepcopy(action)
      params.title = params.title or command.title or ''
      params.scope = scope
      client:request('codeAction/resolveFixAll', params, function(err, resolved)
        if err then
          vim.notify('Roslyn: ' .. tostring(err), vim.log.levels.ERROR)
          return
        end
        if resolved and resolved.edit then
          vim.lsp.util.apply_workspace_edit(resolved.edit, client.offset_encoding)
        end
      end)
    end)
  end

  -- Handle complex completion edits
  vim.lsp.commands['roslyn.client.completionComplexEdit'] = function(command, ctx)
    local edits = command.arguments and command.arguments[1]
    if not edits then return end
    if edits.edit then
      vim.lsp.util.apply_workspace_edit(edits.edit, client.offset_encoding)
    end
  end

  -- Intercept capability registration to optionally strip file watchers
  local config = require('roslyn').config
  if config.filewatching == 'off' then
    local orig = client.handlers['client/registerCapability']
    client.handlers['client/registerCapability'] = function(err, result, ctx, cfg)
      if result and result.registrations then
        result.registrations = vim.tbl_filter(function(reg)
          return reg.method ~= 'workspace/didChangeWatchedFiles'
        end, result.registrations)
      end
      if orig then
        return orig(err, result, ctx, cfg)
      end
    end
  end
end

return M
