--- Source-generated document support for Roslyn LSP.
local M = {}

local scheme = 'roslyn-source-generated'
local buffers = {} -- uri -> { bufnr, result_id }

--- Open a source-generated document by URI.
---@param client vim.lsp.Client
---@param uri string
function M.open(client, uri)
  local existing = buffers[uri]
  if existing and vim.api.nvim_buf_is_valid(existing.bufnr) then
    vim.api.nvim_set_current_buf(existing.bufnr)
    return
  end

  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = 'cs'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].modifiable = false

  -- Extract a reasonable name from the URI
  local name = uri:match('/([^/]+)$') or uri
  vim.api.nvim_buf_set_name(bufnr, scheme .. '://' .. name)

  M.refresh_buf(client, uri, bufnr)
end

--- Refresh the content of a source-generated buffer.
---@param client vim.lsp.Client
---@param uri string
---@param bufnr? integer
function M.refresh_buf(client, uri, bufnr)
  local entry = buffers[uri]
  bufnr = bufnr or (entry and entry.bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  client:request('sourceGeneratedDocument/_roslyn_getText', {
    textDocument = { uri = uri },
    resultId = entry and entry.result_id or vim.NIL,
  }, function(err, result)
    if err or not result then return end
    if result.text then
      vim.bo[bufnr].modifiable = true
      local lines = vim.split(result.text, '\n', { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false
    end
    buffers[uri] = { bufnr = bufnr, result_id = result.resultId }
  end, bufnr)
end

--- Refresh all tracked source-generated buffers.
---@param client vim.lsp.Client
function M.refresh_all(client)
  for uri, entry in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(entry.bufnr) then
      M.refresh_buf(client, uri)
    else
      buffers[uri] = nil
    end
  end
end

return M
