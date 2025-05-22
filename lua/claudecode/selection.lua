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

  local changed = M.has_selection_changed(current_selection)

  if changed then
    M.state.latest_selection = current_selection

    if M.server then
      M.send_selection_update(current_selection)
    end
  end
end

--- Validates if we're in a valid visual selection mode
-- @return boolean, string|nil - true if valid, false and error message if not
local function validate_visual_mode()
  local current_nvim_mode = vim.api.nvim_get_mode().mode
  local fixed_anchor_pos_raw = vim.fn.getpos("v")

  -- Must be in a visual mode
  if not (current_nvim_mode == "v" or current_nvim_mode == "V" or current_nvim_mode == "\22") then
    return false, "not in visual mode"
  end

  -- The 'v' mark must have a non-zero line number
  if fixed_anchor_pos_raw[2] == 0 then
    return false, "no visual selection mark"
  end

  return true, nil
end

--- Determines the effective visual mode character
-- @return string|nil - the visual mode character or nil if invalid
local function get_effective_visual_mode()
  local current_nvim_mode = vim.api.nvim_get_mode().mode
  local visual_fn_mode_char = vim.fn.visualmode()

  if visual_fn_mode_char and visual_fn_mode_char ~= "" then
    return visual_fn_mode_char
  end

  -- Fallback to current mode
  if current_nvim_mode == "V" then
    return "V"
  elseif current_nvim_mode == "v" then
    return "v"
  elseif current_nvim_mode == "\22" then -- Ctrl-V, blockwise
    return "\22"
  end

  return nil
end

--- Gets the start and end coordinates of the visual selection
-- @return table, table - start_coords and end_coords with lnum and col fields
local function get_selection_coordinates()
  local fixed_anchor_pos_raw = vim.fn.getpos("v")
  local current_cursor_nvim = vim.api.nvim_win_get_cursor(0)

  -- Convert to 1-indexed line and 1-indexed column for consistency
  local p1 = { lnum = fixed_anchor_pos_raw[2], col = fixed_anchor_pos_raw[3] }
  local p2 = { lnum = current_cursor_nvim[1], col = current_cursor_nvim[2] + 1 }

  -- Determine chronological start/end based on line, then column
  if p1.lnum < p2.lnum or (p1.lnum == p2.lnum and p1.col <= p2.col) then
    return p1, p2
  else
    return p2, p1
  end
end

--- Extracts text for linewise visual selection
-- @param lines_content table - array of line strings
-- @param start_coords table - start coordinates
-- @return string - the extracted text
local function extract_linewise_text(lines_content, start_coords)
  start_coords.col = 1 -- Linewise selection effectively starts at column 1
  return table.concat(lines_content, "\n")
end

--- Extracts text for characterwise visual selection
-- @param lines_content table - array of line strings
-- @param start_coords table - start coordinates
-- @param end_coords table - end coordinates
-- @return string|nil - the extracted text or nil if invalid
local function extract_characterwise_text(lines_content, start_coords, end_coords)
  if start_coords.lnum == end_coords.lnum then
    -- Single line selection
    if not lines_content[1] then
      return nil
    end
    return string.sub(lines_content[1], start_coords.col, end_coords.col)
  else
    -- Multi-line selection
    if not lines_content[1] or not lines_content[#lines_content] then
      return nil
    end

    local text_parts = {}
    -- First line: from start_coords.col to end of line
    table.insert(text_parts, string.sub(lines_content[1], start_coords.col))
    -- Middle lines (if any)
    for i = 2, #lines_content - 1 do
      table.insert(text_parts, lines_content[i])
    end
    -- Last line: from beginning to end_coords.col
    table.insert(text_parts, string.sub(lines_content[#lines_content], 1, end_coords.col))
    return table.concat(text_parts, "\n")
  end
end

--- Calculates LSP-compatible position coordinates
-- @param start_coords table - start coordinates
-- @param end_coords table - end coordinates
-- @param visual_mode string - the visual mode character
-- @param lines_content table - array of line strings
-- @return table - LSP position object with start and end fields
local function calculate_lsp_positions(start_coords, end_coords, visual_mode, lines_content)
  local lsp_start_line = start_coords.lnum - 1
  local lsp_end_line = end_coords.lnum - 1
  local lsp_start_char, lsp_end_char

  if visual_mode == "V" then
    lsp_start_char = 0 -- Linewise selection always starts at character 0
    -- For linewise, LSP end char is length of the last selected line
    if #lines_content > 0 and lines_content[#lines_content] then
      lsp_end_char = #lines_content[#lines_content]
    else
      lsp_end_char = 0
    end
  else
    -- For characterwise/blockwise
    lsp_start_char = start_coords.col - 1
    lsp_end_char = end_coords.col
  end

  return {
    start = { line = lsp_start_line, character = lsp_start_char },
    ["end"] = { line = lsp_end_line, character = lsp_end_char },
  }
end

--- Gets the current visual selection details.
-- @return table|nil A table containing selection text, file path, URL, and
--                   start/end positions, or nil if no visual selection exists.
function M.get_visual_selection()
  -- Validate visual mode
  local valid = validate_visual_mode()
  if not valid then
    return nil
  end

  -- Get effective visual mode
  local visual_mode = get_effective_visual_mode()
  if not visual_mode then
    return nil
  end

  -- Get selection coordinates
  local start_coords, end_coords = get_selection_coordinates()

  -- Get buffer information
  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)

  -- Fetch lines content
  local lines_content = vim.api.nvim_buf_get_lines(
    current_buf,
    start_coords.lnum - 1, -- Convert to 0-indexed
    end_coords.lnum, -- nvim_buf_get_lines end is exclusive
    false
  )

  if #lines_content == 0 then
    return nil
  end

  -- Extract text based on visual mode
  local final_text
  if visual_mode == "V" then
    final_text = extract_linewise_text(lines_content, start_coords)
  elseif visual_mode == "v" or visual_mode == "\22" then
    final_text = extract_characterwise_text(lines_content, start_coords, end_coords)
    if not final_text then
      return nil
    end
  else
    return nil
  end

  -- Calculate LSP positions
  local lsp_positions = calculate_lsp_positions(start_coords, end_coords, visual_mode, lines_content)

  return {
    text = final_text or "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = lsp_positions.start,
      ["end"] = lsp_positions["end"],
      isEmpty = (not final_text or #final_text == 0),
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
