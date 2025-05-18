-- Selection tracking for Claude Code Neovim integration
local M = {}

-- Selection state
M.state = {
  latest_selection = nil,
  tracking_enabled = false,
  debounce_timer = nil,
  debounce_ms = 300, -- Default debounce time in milliseconds
}

-- Enable selection tracking
function M.enable(server)
  if M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = true
  M.server = server

  -- Set up autocommands for tracking selections
  M._create_autocommands()
end

-- Disable selection tracking
function M.disable()
  if not M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = false

  -- Remove autocommands
  M._clear_autocommands()

  -- Clear state
  M.state.latest_selection = nil
  M.server = nil

  -- Clear debounce timer if active
  if M.state.debounce_timer then
    vim.loop.timer_stop(M.state.debounce_timer)
    M.state.debounce_timer = nil
  end
end

-- Create autocommands for tracking selections
function M._create_autocommands()
  local group = vim.api.nvim_create_augroup("ClaudeCodeSelection", { clear = true })

  -- Track selection changes in various modes
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      M.on_cursor_moved()
    end,
  })

  -- Track mode changes
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      M.on_mode_changed()
    end,
  })

  -- Track buffer content changes
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function()
      M.on_text_changed()
    end,
  })
end

-- Clear autocommands
function M._clear_autocommands()
  vim.api.nvim_clear_autocmds({ group = "ClaudeCodeSelection" })
end

-- Handle cursor movement events
function M.on_cursor_moved()
  -- Debounce the update to avoid sending too many updates
  M.debounce_update()
end

-- Handle mode change events
function M.on_mode_changed()
  -- Update selection immediately on mode change
  M.update_selection()
end

-- Handle text change events
function M.on_text_changed()
  -- Debounce the update
  M.debounce_update()
end

-- Debounce selection updates
function M.debounce_update()
  -- Cancel existing timer if active
  if M.state.debounce_timer then
    vim.loop.timer_stop(M.state.debounce_timer)
  end

  -- Create new timer for debounced update
  M.state.debounce_timer = vim.defer_fn(function()
    M.update_selection()
    M.state.debounce_timer = nil
  end, M.state.debounce_ms)
end

-- Update the current selection
function M.update_selection()
  if not M.state.tracking_enabled then
    return
  end

  local current_mode = vim.api.nvim_get_mode().mode

  -- Get selection based on mode
  local current_selection
  if current_mode == "v" or current_mode == "V" or current_mode == "\022" then
    -- Visual mode selection
    current_selection = M.get_visual_selection()
  else
    -- Normal mode - no selection, just track cursor position
    current_selection = M.get_cursor_position()
  end

  -- Check if selection has changed
  if M.has_selection_changed(current_selection) then
    -- Store latest selection
    M.state.latest_selection = current_selection

    -- Send selection update if connected to Claude
    if M.server then
      M.send_selection_update(current_selection)
    end
  end
end

-- Get the current visual selection
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- If no selection, return nil
  if start_pos[2] == 0 and end_pos[2] == 0 then
    return nil
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  -- Get selection text
  local lines = vim.api.nvim_buf_get_lines(
    current_buf,
    start_pos[2] - 1, -- 0-indexed line
    end_pos[2], -- end line is exclusive
    false
  )

  -- Adjust for column positions
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end

  -- Combine lines
  local text = table.concat(lines, "\n")

  return {
    text = text,
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
      ["end"] = { line = end_pos[2] - 1, character = end_pos[3] },
      isEmpty = false,
    },
  }
end

-- Get the current cursor position (no selection)
function M.get_cursor_position()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  return {
    text = "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = cursor_pos[1] - 1, character = cursor_pos[2] },
      ["end"] = { line = cursor_pos[1] - 1, character = cursor_pos[2] },
      isEmpty = true,
    },
  }
end

-- Check if selection has changed
function M.has_selection_changed(new_selection)
  if not M.state.latest_selection then
    return true
  end

  local current = M.state.latest_selection

  -- Compare file paths
  if current.filePath ~= new_selection.filePath then
    return true
  end

  -- Compare text content
  if current.text ~= new_selection.text then
    return true
  end

  -- Compare selection positions
  if
    current.selection.start.line ~= new_selection.selection.start.line
    or current.selection.start.character ~= new_selection.selection.start.character
    or current.selection["end"].line ~= new_selection.selection["end"].line
    or current.selection["end"].character ~= new_selection.selection["end"].character
  then
    return true
  end

  return false
end

-- Send selection update to Claude
function M.send_selection_update(selection)
  -- Send via WebSocket
  M.server.broadcast("selection_changed", selection)
end

-- Get the latest selection
function M.get_latest_selection()
  return M.state.latest_selection
end

-- Send current selection to Claude (user command)
function M.send_current_selection()
  if not M.state.tracking_enabled or not M.server then
    vim.api.nvim_err_writeln("Claude Code is not running")
    return
  end

  -- Force an immediate selection update
  M.update_selection()

  -- Get the latest selection
  local selection = M.state.latest_selection

  if not selection then
    vim.api.nvim_err_writeln("No selection available")
    return
  end

  -- Send it to Claude
  M.send_selection_update(selection)

  vim.api.nvim_echo({ { "Selection sent to Claude", "Normal" } }, false, {})
end

return M
