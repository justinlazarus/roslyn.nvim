--- User-facing :Roslyn commands.
local M = {}

local sln = require('roslyn.sln')
local sourcegen = require('roslyn.sourcegen')

--- Get the active Roslyn LSP client.
---@return vim.lsp.Client|nil
local function get_client()
  local clients = vim.lsp.get_clients({ name = 'roslyn' })
  return clients[1]
end

--- Register all :Roslyn subcommands.
function M.setup()
  vim.api.nvim_create_user_command('Roslyn', function(opts)
    local subcmd = opts.fargs[1]
    local handler = M.subcommands[subcmd]
    if not handler then
      local available = table.concat(vim.tbl_keys(M.subcommands), ', ')
      vim.notify('Roslyn: unknown command "' .. (subcmd or '') .. '". Available: ' .. available, vim.log.levels.ERROR)
      return
    end
    handler(opts)
  end, {
    nargs = '+',
    complete = function(_, line)
      local parts = vim.split(vim.trim(line), '%s+')
      if #parts <= 2 then
        return vim.tbl_keys(M.subcommands)
      end
      return {}
    end,
    desc = 'Roslyn LSP commands',
  })
end

M.subcommands = {}

--- :Roslyn info — show server status, solution, and capabilities.
M.subcommands.info = function()
  local client = get_client()
  if not client then
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
    return
  end

  local info_lines = {
    'Roslyn LSP Info',
    string.rep('─', 40),
    'Client ID:   ' .. client.id,
    'Name:        ' .. client.name,
    'PID:         ' .. (client.rpc and client.rpc.pid or 'N/A'),
    'Root:        ' .. (client.root_dir or 'N/A'),
    'Status:      ' .. (client.initialized and 'initialized' or 'starting'),
  }

  local target = vim.g.roslyn_lsp_target
  if target then
    table.insert(info_lines, 'Target:      ' .. target)
  end

  local caps = client.server_capabilities
  if caps then
    table.insert(info_lines, '')
    table.insert(info_lines, 'Capabilities')
    table.insert(info_lines, string.rep('─', 40))
    local cap_list = {
      { 'completionProvider', 'Completion' },
      { 'hoverProvider', 'Hover' },
      { 'definitionProvider', 'Go to Definition' },
      { 'referencesProvider', 'References' },
      { 'documentFormattingProvider', 'Formatting' },
      { 'codeActionProvider', 'Code Actions' },
      { 'renameProvider', 'Rename' },
      { 'signatureHelpProvider', 'Signature Help' },
      { 'documentSymbolProvider', 'Document Symbols' },
      { 'workspaceSymbolProvider', 'Workspace Symbols' },
      { 'implementationProvider', 'Implementation' },
      { 'typeDefinitionProvider', 'Type Definition' },
      { 'inlayHintProvider', 'Inlay Hints' },
      { 'semanticTokensProvider', 'Semantic Tokens' },
    }
    for _, cap in ipairs(cap_list) do
      local val = caps[cap[1]]
      local status = val and (val ~= false) and 'yes' or 'no'
      table.insert(info_lines, string.format('  %-20s %s', cap[2], status))
    end
  end

  -- Show in a scratch buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, info_lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].filetype = 'markdown'
  vim.cmd('botright split')
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_height(0, math.min(#info_lines + 2, 25))
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = bufnr, silent = true })
end

--- :Roslyn target — switch solution/project target.
M.subcommands.target = function()
  local client = get_client()
  local bufpath = vim.api.nvim_buf_get_name(0)
  if bufpath == '' then
    vim.notify('Roslyn: no file in buffer', vim.log.levels.WARN)
    return
  end

  local start_dir = vim.fs.dirname(bufpath)
  local solutions = sln.find_solutions(start_dir)

  -- Also try broad search
  local git_root = vim.fs.find('.git', { path = start_dir, upward = true, type = 'directory' })
  if git_root and #git_root > 0 then
    local broad = sln.find_solutions_broad(vim.fs.dirname(git_root[1]))
    for _, s in ipairs(broad) do
      if not vim.tbl_contains(solutions, s) then
        table.insert(solutions, s)
      end
    end
  end

  -- Also add csproj files
  local projects = sln.find_projects(start_dir)
  local items = {}
  for _, s in ipairs(solutions) do
    table.insert(items, { path = s, type = 'solution' })
  end
  for _, p in ipairs(projects) do
    table.insert(items, { path = p, type = 'project' })
  end

  if #items == 0 then
    vim.notify('Roslyn: no solution or project files found', vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = 'Select target',
    format_item = function(item)
      return string.format('[%s] %s', item.type, vim.fn.fnamemodify(item.path, ':~:.'))
    end,
  }, function(selected)
    if not selected then return end
    vim.g.roslyn_lsp_target = selected.path

    if client then
      -- Send the appropriate open notification
      if selected.type == 'solution' then
        client:notify('solution/open', { solution = vim.uri_from_fname(selected.path) })
      else
        client:notify('project/open', { projects = { vim.uri_from_fname(selected.path) } })
      end
      vim.notify('Roslyn: switched to ' .. vim.fn.fnamemodify(selected.path, ':t'), vim.log.levels.INFO)
    else
      vim.notify('Roslyn: target set, restart server to apply', vim.log.levels.INFO)
    end
  end)
end

--- :Roslyn restart — restart the LSP server.
M.subcommands.restart = function()
  local client = get_client()
  if client then
    local root = client.root_dir
    vim.notify('Roslyn: restarting...', vim.log.levels.INFO)
    client:stop()
    vim.defer_fn(function()
      -- Re-enable will start a new client for attached buffers
      vim.lsp.enable('roslyn')
    end, 500)
  else
    vim.notify('Roslyn: no active client to restart', vim.log.levels.WARN)
  end
end

--- :Roslyn stop — stop the LSP server.
M.subcommands.stop = function()
  local client = get_client()
  if client then
    client:stop()
    vim.notify('Roslyn: stopped', vim.log.levels.INFO)
  else
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
  end
end

--- :Roslyn restore — trigger dotnet restore.
M.subcommands.restore = function()
  local client = get_client()
  if not client then
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
    return
  end

  -- Try via LSP first
  client:request('workspace/_roslyn_restore', {}, function(err, result)
    if err then
      -- Fall back to shell command
      local root = client.root_dir or vim.fn.getcwd()
      vim.notify('Roslyn: running dotnet restore...', vim.log.levels.INFO)
      vim.system({ 'dotnet', 'restore' }, { cwd = root }, function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            vim.notify('Roslyn: restore complete', vim.log.levels.INFO)
            vim.api.nvim_exec_autocmds('User', { pattern = 'RoslynRestoreComplete' })
          else
            vim.notify('Roslyn: restore failed\n' .. (obj.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
      return
    end
    vim.notify('Roslyn: restore initiated via LSP', vim.log.levels.INFO)
  end)
end

--- :Roslyn log — open the LSP log.
M.subcommands.log = function()
  vim.cmd.edit(vim.lsp.log.get_filename())
end

--- :Roslyn open_sourcegen — open a source-generated document.
M.subcommands.open_sourcegen = function(opts)
  local client = get_client()
  if not client then
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
    return
  end
  local uri = opts.fargs[2]
  if not uri then
    vim.notify('Roslyn: provide a source-generated document URI', vim.log.levels.WARN)
    return
  end
  sourcegen.open(client, uri)
end

--- :Roslyn incoming_calls — show incoming calls to symbol under cursor.
M.subcommands.incoming_calls = function()
  vim.lsp.buf.incoming_calls()
end

--- :Roslyn outgoing_calls — show outgoing calls from symbol under cursor.
M.subcommands.outgoing_calls = function()
  vim.lsp.buf.outgoing_calls()
end

--- :Roslyn references — find all references to symbol under cursor.
M.subcommands.references = function()
  vim.lsp.buf.references()
end

--- :Roslyn implementation — go to implementation.
M.subcommands.implementation = function()
  vim.lsp.buf.implementation()
end

--- :Roslyn type_definition — go to type definition.
M.subcommands.type_definition = function()
  vim.lsp.buf.type_definition()
end

--- :Roslyn document_symbols — list symbols in current document.
M.subcommands.document_symbols = function()
  vim.lsp.buf.document_symbol()
end

--- :Roslyn workspace_symbols — search symbols across workspace.
M.subcommands.workspace_symbols = function(opts)
  local query = opts.fargs[2] or ''
  vim.lsp.buf.workspace_symbol(query)
end

--- :Roslyn organize_imports — organize using directives.
M.subcommands.organize_imports = function()
  local client = get_client()
  if not client then
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
    return
  end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(),
    context = { diagnostics = {}, only = { 'source.organizeImports' } },
  }
  client:request('textDocument/codeAction', params, function(err, result)
    if err then
      vim.notify('Roslyn: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if not result or #result == 0 then
      vim.notify('Roslyn: no import changes needed', vim.log.levels.INFO)
      return
    end
    for _, action in ipairs(result) do
      if action.edit then
        vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding or 'utf-16')
      elseif action.command then
        client:exec_cmd(action.command)
      end
    end
  end)
end

--- :Roslyn fix_all — apply fix-all code actions.
M.subcommands.fix_all = function()
  local client = get_client()
  if not client then
    vim.notify('Roslyn: no active client', vim.log.levels.WARN)
    return
  end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(),
    context = { diagnostics = {}, only = { 'source.fixAll' } },
  }
  client:request('textDocument/codeAction', params, function(err, result)
    if err then
      vim.notify('Roslyn: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if not result or #result == 0 then
      vim.notify('Roslyn: no fix-all actions available', vim.log.levels.INFO)
      return
    end
    vim.ui.select(result, {
      prompt = 'Fix All',
      format_item = function(item) return item.title end,
    }, function(selected)
      if not selected then return end
      if selected.edit then
        vim.lsp.util.apply_workspace_edit(selected.edit, client.offset_encoding or 'utf-16')
      elseif selected.command then
        client:exec_cmd(selected.command)
      end
    end)
  end)
end

return M
