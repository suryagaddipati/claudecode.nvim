---
-- Manages selection tracking and communication with the Claude server.
-- This module handles enabling/disabling selection tracking, debouncing updates,
-- determining the current selection (visual or cursor position), and sending
-- updates to the Claude server.
-- @module claudecode.selection
local M = {}

-- Selection state
M.state = {
  latest_selection = nil,
  tracking_enabled = false,
  debounce_timer = nil,
  debounce_ms = 300, -- Default debounce time in milliseconds
}

--- Enables selection tracking.
-- Sets up autocommands to monitor cursor movements, mode changes, and text changes.
-- @param server table The server object to use for communication.
function M.enable(server)
  if M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = true
  M.server = server

  M._create_autocommands()
end

--- Disables selection tracking.
-- Clears autocommands, resets internal state, and stops any active debounce timers.
function M.disable()
  if not M.state.tracking_enabled then
    return
  end

  M.state.tracking_enabled = false

  M._clear_autocommands()

  M.state.latest_selection = nil
  M.server = nil

  if M.state.debounce_timer then
    vim.loop.timer_stop(M.state.debounce_timer)
    M.state.debounce_timer = nil
  end
end

--- Creates autocommands for tracking selections.
-- Sets up listeners for CursorMoved, CursorMovedI, ModeChanged, and TextChanged events.
-- @local
function M._create_autocommands()
  local group = vim.api.nvim_create_augroup("ClaudeCodeSelection", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      M.on_cursor_moved()
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      M.on_mode_changed()
    end,
  })

  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function()
      M.on_text_changed()
    end,
  })
end

--- Clears the autocommands related to selection tracking.
-- @local
function M._clear_autocommands()
  vim.api.nvim_clear_autocmds({ group = "ClaudeCodeSelection" })
end

--- Handles cursor movement events.
-- Triggers a debounced update of the selection.
function M.on_cursor_moved()
  -- Debounce the update to avoid sending too many updates
  M.debounce_update()
end

--- Handles mode change events.
-- Triggers an immediate update of the selection.
function M.on_mode_changed()
  -- Update selection immediately on mode change
  M.update_selection()
end

--- Handles text change events.
-- Triggers a debounced update of the selection.
function M.on_text_changed()
  M.debounce_update()
end

--- Debounces selection updates.
-- Ensures that `update_selection` is not called too frequently by deferring
-- its execution.
function M.debounce_update()
  if M.state.debounce_timer then
    vim.loop.timer_stop(M.state.debounce_timer)
  end

  M.state.debounce_timer = vim.defer_fn(function()
    M.update_selection()
    M.state.debounce_timer = nil
  end, M.state.debounce_ms)
end

--- Updates the current selection state.
-- Determines the current selection based on the editor mode (visual or normal)
-- and sends an update to the server if the selection has changed.
function M.update_selection()
  if not M.state.tracking_enabled then
    return
  end

  local current_mode = vim.api.nvim_get_mode().mode

  local current_selection
  if current_mode == "v" or current_mode == "V" or current_mode == "\022" then
    current_selection = M.get_visual_selection()
  else
    current_selection = M.get_cursor_position()
  end

  if M.has_selection_changed(current_selection) then
    M.state.latest_selection = current_selection

    if M.server then
      M.send_selection_update(current_selection)
    end
  end
end

--- Gets the current visual selection details.
-- @return table|nil A table containing selection text, file path, URL, and
--                   start/end positions, or nil if no visual selection exists.
function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- If no selection, return nil
  if start_pos[2] == 0 and end_pos[2] == 0 then
    return nil
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  local lines = vim.api.nvim_buf_get_lines(
    current_buf,
    start_pos[2] - 1, -- 0-indexed line
    end_pos[2], -- end line is exclusive
    false
  )

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end

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

--- Gets the current cursor position when no visual selection is active.
-- @return table A table containing an empty text, file path, URL, and cursor
--               position as start/end, with isEmpty set to true.
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

--- Checks if the selection has changed compared to the latest stored selection.
-- @param new_selection table|nil The new selection object to compare.
-- @return boolean true if the selection has changed, false otherwise.
function M.has_selection_changed(new_selection)
  local old_selection = M.state.latest_selection

  if not new_selection then
    -- If old selection was also nil, no change. Otherwise (old selection existed), it's a change.
    return old_selection ~= nil
  end

  if not old_selection then
    return true
  end

  if old_selection.filePath ~= new_selection.filePath then
    return true
  end

  if old_selection.text ~= new_selection.text then
    return true
  end

  if
    old_selection.selection.start.line ~= new_selection.selection.start.line
    or old_selection.selection.start.character ~= new_selection.selection.start.character
    or old_selection.selection["end"].line ~= new_selection.selection["end"].line
    or old_selection.selection["end"].character ~= new_selection.selection["end"].character
  then
    return true
  end

  return false
end

--- Sends the selection update to the Claude server.
-- @param selection table The selection object to send.
function M.send_selection_update(selection)
  M.server.broadcast("selection_changed", selection)
end

--- Gets the latest recorded selection.
-- @return table|nil The latest selection object, or nil if none recorded.
function M.get_latest_selection()
  return M.state.latest_selection
end

--- Sends the current selection to Claude.
-- This function is typically invoked by a user command. It forces an immediate
-- update and sends the latest selection.
function M.send_current_selection()
  if not M.state.tracking_enabled or not M.server then
    vim.api.nvim_err_writeln("Claude Code is not running")
    return
  end

  M.update_selection()

  local selection = M.state.latest_selection

  if not selection then
    vim.api.nvim_err_writeln("No selection available")
    return
  end

  M.send_selection_update(selection)

  vim.api.nvim_echo({ { "Selection sent to Claude", "Normal" } }, false, {})
end

return M
