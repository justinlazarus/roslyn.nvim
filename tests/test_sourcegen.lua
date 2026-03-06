local sourcegen = require('roslyn.sourcegen')

describe('sourcegen.open', function()
  it('creates a new buffer for a source-generated URI', function()
    -- Create a mock client
    local request_called = false
    local mock_client = {
      request = function(_, method, params, callback, bufnr)
        request_called = true
        -- Simulate empty response
        callback(nil, { text = '// generated\nclass Foo {}', resultId = 'rid1' })
      end,
    }

    local uri = 'source-generated://assembly/MyGen/File.cs'
    sourcegen.open(mock_client, uri)

    ok(request_called, 'should call client:request')

    -- The current buffer should be the source-generated buffer
    local bufnr = vim.api.nvim_get_current_buf()
    eq('cs', vim.bo[bufnr].filetype)
    eq('nofile', vim.bo[bufnr].buftype)
    eq(false, vim.bo[bufnr].modifiable)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq('// generated', lines[1])
    eq('class Foo {}', lines[2])

    -- Clean up
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('sourcegen.refresh_all', function()
  it('does not error with no tracked buffers', function()
    local mock_client = {
      request = function() end,
    }
    -- Should not error
    sourcegen.refresh_all(mock_client)
  end)
end)
