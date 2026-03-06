--- Lightweight LSP progress display for Roslyn.
--- Shows a spinner + message in a small float anchored to the bottom-right.
local M = {}

local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spinner_idx = 1
local timer = nil
local win_id = nil
local buf_id = nil
local tasks = {} -- token -> { title, message, percentage, done }
local done_ttl = 3 -- seconds to keep completed tasks visible
local done_timers = {} -- token -> uv_timer

local function get_buf()
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then return buf_id end
  buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].buftype = 'nofile'
  vim.bo[buf_id].filetype = 'roslyn-progress'
  return buf_id
end

local function close_win()
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end
  win_id = nil
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end
  buf_id = nil
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function render()
  -- Build lines from active tasks
  local lines = {}
  local max_width = 0
  for _, task in pairs(tasks) do
    local parts = {}
    if not task.done then
      table.insert(parts, spinner_frames[spinner_idx])
    else
      table.insert(parts, '✓')
    end
    if task.title then
      table.insert(parts, task.title)
    end
    if task.message then
      table.insert(parts, task.message)
    end
    if task.percentage and not task.done then
      table.insert(parts, string.format('(%d%%)', task.percentage))
    end
    local line = table.concat(parts, ' ')
    table.insert(lines, line)
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  if #lines == 0 then
    close_win()
    stop_timer()
    return
  end

  local b = get_buf()
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)

  local width = math.max(max_width, 10)
  local height = #lines
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight - 1

  local row = editor_height - height
  local col = editor_width - width - 2

  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_set_config(win_id, {
      relative = 'editor',
      row = row,
      col = col,
      width = width,
      height = height,
    })
  else
    win_id = vim.api.nvim_open_win(b, false, {
      relative = 'editor',
      row = row,
      col = col,
      width = width,
      height = height,
      anchor = 'NW',
      style = 'minimal',
      border = 'none',
      focusable = false,
      noautocmd = true,
      zindex = 45,
    })
    vim.api.nvim_set_option_value('winblend', 0, { win = win_id })
    vim.api.nvim_set_option_value('winhighlight', 'Normal:Comment', { win = win_id })
  end
end

local function ensure_timer()
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(0, 80, vim.schedule_wrap(function()
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    render()
  end))
end

local function remove_task(token)
  tasks[token] = nil
  if done_timers[token] then
    done_timers[token]:stop()
    done_timers[token]:close()
    done_timers[token] = nil
  end
  -- If no tasks left, clean up
  if not next(tasks) then
    vim.schedule(function()
      close_win()
      stop_timer()
    end)
  end
end

--- Handle an LSP progress event.
---@param token any
---@param value table { kind: "begin"|"report"|"end", title?, message?, percentage? }
---@param client_name string
function M.on_progress(token, value, client_name)
  if not value or type(value) ~= 'table' or not value.kind then return end

  if value.kind == 'begin' then
    -- Cancel any pending removal timer for this token (e.g., reusing token across phases)
    if done_timers[token] then
      done_timers[token]:stop()
      done_timers[token]:close()
      done_timers[token] = nil
    end
    tasks[token] = {
      title = value.title,
      message = value.message,
      percentage = value.percentage,
      done = false,
    }
    ensure_timer()
  elseif value.kind == 'report' then
    local task = tasks[token]
    if task then
      task.message = value.message or task.message
      task.percentage = value.percentage or task.percentage
    end
  elseif value.kind == 'end' then
    local task = tasks[token]
    if task then
      task.done = true
      task.message = value.message or 'done'
      task.percentage = nil
      -- Schedule removal after TTL
      local t = vim.uv.new_timer()
      done_timers[token] = t
      t:start(done_ttl * 1000, 0, function()
        remove_task(token)
      end)
    end
  end
end

--- Show a custom progress message (e.g., workspace loading).
---@param token string
---@param title string
function M.begin(token, title)
  M.on_progress(token, { kind = 'begin', title = title }, 'roslyn')
end

--- Complete a custom progress message.
---@param token string
---@param message? string
function M.finish(token, message)
  M.on_progress(token, { kind = 'end', message = message or 'done' }, 'roslyn')
end

--- Register autocmd to listen for LspProgress events from roslyn.
function M.setup()
  vim.api.nvim_create_autocmd('LspProgress', {
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if not client or client.name ~= 'roslyn' then return end
      local data = event.data
      M.on_progress(data.token, data.value, client.name)
    end,
    desc = 'Roslyn LSP progress display',
  })
end

return M
