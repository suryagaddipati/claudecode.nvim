# OpenDiff Tool MCP Compliance Implementation Plan

This document provides a comprehensive specification for making the `openDiff` tool in the Neovim Claude Code integration fully compliant with the Model Context Protocol (MCP) specification as defined in `findings.md`.

## Executive Summary

The current `openDiff` implementation is **not MCP-compliant** and requires significant architectural changes to support blocking operations, proper event monitoring, and correct response formats. This plan integrates insights from multiple architectural reviews to provide a robust, production-ready solution.

## Current State Analysis

### Compliance Gaps

1. **Non-blocking Operation**: Returns immediately instead of waiting for user interaction
2. **Incorrect Response Format**: Returns simple object instead of MCP content array
3. **Missing Event Monitoring**: No listeners for save/close/accept/reject events
4. **No State Management**: Doesn't track diff state or handle concurrent operations
5. **Improper Resource Management**: No cleanup mechanisms for temporary resources

### Required MCP Behavior (per findings.md)

- **Blocking operation** that waits indefinitely for user interaction
- Returns specific responses based on user actions:
  - `FILE_SAVED` + file contents when user saves/accepts changes
  - `DIFF_REJECTED` + tab_name when user closes/rejects diff
- Monitors tab close events, file save events, and diff acceptance/rejection
- Uses MCP content array format: `[{"type": "text", "text": "..."}]`
- Handles concurrent diff operations with unique identifiers

## Implementation Architecture

### Phase 1: Core Architecture Enhancements

#### 1.1 Enhanced diff.lua Module

**New Functions:**

```lua
-- Primary blocking function
local function open_diff_blocking(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Returns: promise-like table with async resolution
end

-- Scratch buffer management
local function create_new_content_buffer(content, filename)
  local buf = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
  vim.api.nvim_buf_set_name(buf, filename)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, '\n'))
  return buf
end

-- State management
local function register_diff_state(tab_name, diff_data)
  -- Track active diff with cleanup callbacks
end

local function cleanup_diff_state(tab_name, reason)
  -- Clean up autocmds, buffers, and state
end
```

#### 1.2 State Management System

**Global State Structure:**

```lua
local active_diffs = {
  [tab_name] = {
    old_file_path = string,
    new_file_path = string,
    new_file_contents = string,
    old_buffer = number,        -- buffer ID for old content
    new_buffer = number,        -- buffer ID for new content (scratch)
    diff_window = number,       -- window ID containing diff
    autocmd_ids = {number},     -- autocmd IDs for cleanup
    created_at = number,        -- timestamp for tracking
    status = "pending",         -- "pending", "saved", "rejected"
    resolution_callback = function, -- coroutine resume function
    result_content = table,     -- final MCP response content
  }
}
```

#### 1.3 Event Monitoring System

**Required Autocmds:**

```lua
-- File save detection
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*",
  callback = function(args)
    local tab_name = find_diff_by_buffer(args.buf)
    if tab_name then
      resolve_diff_as_saved(tab_name, args.buf)
    end
  end
})

-- Tab/buffer close detection
vim.api.nvim_create_autocmd({"BufDelete", "TabClosed"}, {
  pattern = "*",
  callback = function(args)
    local tab_name = find_diff_by_buffer(args.buf)
    if tab_name then
      resolve_diff_as_rejected(tab_name)
    end
  end
})

-- Neovim shutdown handling
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    cleanup_all_active_diffs("shutdown")
  end
})
```

### Phase 2: Blocking Implementation

#### 2.1 Coroutine-Based Waiting

**Updated openDiff Handler:**

```lua
local function handler(params)
  -- Validate required parameters
  local required_params = {"old_file_path", "new_file_path", "new_file_contents", "tab_name"}
  for _, param_name in ipairs(required_params) do
    if not params[param_name] then
      error({
        code = -32602, -- Invalid params
        message = "Invalid params",
        data = "Missing required parameter: " .. param_name,
      })
    end
  end

  -- Check for existing diff with same tab_name
  if active_diffs[params.tab_name] then
    cleanup_diff_state(params.tab_name, "replaced")
  end

  -- Set up blocking diff operation
  local co = coroutine.running()
  if not co then
    error({
      code = -32000,
      message = "Internal server error",
      data = "openDiff must run in coroutine context"
    })
  end

  -- Initialize diff state and monitoring
  local success, err = pcall(setup_blocking_diff, params, function(result)
    coroutine.resume(co, result)
  end)

  if not success then
    error({
      code = -32000,
      message = "Error setting up diff",
      data = tostring(err)
    })
  end

  -- Yield and wait for user action
  local result = coroutine.yield()

  -- Clean up diff state
  cleanup_diff_state(params.tab_name, "completed")

  return result
end
```

#### 2.2 Setup Blocking Diff Function

```lua
local function setup_blocking_diff(params, resolution_callback)
  local tab_name = params.tab_name

  -- Create scratch buffer for new content
  local new_buffer = create_new_content_buffer(
    params.new_file_contents,
    params.new_file_path
  )

  -- Open old file buffer
  local old_buffer = vim.api.nvim_create_buf(false, false)
  local old_content_ok, old_content = pcall(function()
    local file = io.open(params.old_file_path, 'r')
    if not file then
      error("Cannot open old file: " .. params.old_file_path)
    end
    local content = file:read('*all')
    file:close()
    return content
  end)

  if not old_content_ok then
    error("Failed to read old file: " .. old_content)
  end

  vim.api.nvim_buf_set_lines(old_buffer, 0, -1, false, vim.split(old_content, '\n'))
  vim.api.nvim_buf_set_name(old_buffer, params.old_file_path)

  -- Create diff view
  local diff_window = create_diff_view(old_buffer, new_buffer, tab_name)

  -- Register autocmds for this specific diff
  local autocmd_ids = register_diff_autocmds(tab_name, new_buffer, old_buffer)

  -- Store diff state
  active_diffs[tab_name] = {
    old_file_path = params.old_file_path,
    new_file_path = params.new_file_path,
    new_file_contents = params.new_file_contents,
    old_buffer = old_buffer,
    new_buffer = new_buffer,
    diff_window = diff_window,
    autocmd_ids = autocmd_ids,
    created_at = vim.fn.localtime(),
    status = "pending",
    resolution_callback = resolution_callback,
    result_content = nil,
  }

end
```

#### 2.3 MCP Content Format Compliance

**Response Format Implementation:**

```lua
local function resolve_diff_as_saved(tab_name, buffer_id)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= "pending" then
    return
  end

  -- Get final file contents
  local final_content = table.concat(
    vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false),
    '\n'
  )

  -- Create MCP-compliant response
  local result = {
    content = {
      {type = "text", text = "FILE_SAVED"},
      {type = "text", text = final_content}
    }
  }

  diff_data.status = "saved"
  diff_data.result_content = result

  if diff_data.resolution_callback then
    diff_data.resolution_callback(result)
  end
end

local function resolve_diff_as_rejected(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= "pending" then
    return
  end

  -- Create MCP-compliant response
  local result = {
    content = {
      {type = "text", text = "DIFF_REJECTED"},
      {type = "text", text = tab_name}
    }
  }

  diff_data.status = "rejected"
  diff_data.result_content = result

  if diff_data.resolution_callback then
    diff_data.resolution_callback(result)
  end
end
```

### Phase 3: Event Integration & Resource Management

#### 3.1 Autocmd Registration System

```lua
local function register_diff_autocmds(tab_name, new_buffer, old_buffer)
  local autocmd_ids = {}

  -- Save event monitoring
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = new_buffer,
    callback = function()
      resolve_diff_as_saved(tab_name, new_buffer)
    end
  })

  -- Close event monitoring
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufDelete", {
    buffer = new_buffer,
    callback = function()
      resolve_diff_as_rejected(tab_name)
    end
  })

  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufDelete", {
    buffer = old_buffer,
    callback = function()
      resolve_diff_as_rejected(tab_name)
    end
  })

  return autocmd_ids
end
```

#### 3.2 Cleanup Management

```lua
local function cleanup_diff_state(tab_name, reason)
  local diff_data = active_diffs[tab_name]
  if not diff_data then
    return
  end

  -- Clean up autocmds
  for _, autocmd_id in ipairs(diff_data.autocmd_ids or {}) do
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
  end

  -- Clean up buffers
  if diff_data.new_buffer and vim.api.nvim_buf_is_valid(diff_data.new_buffer) then
    pcall(vim.api.nvim_buf_delete, diff_data.new_buffer, {force = true})
  end

  if diff_data.old_buffer and vim.api.nvim_buf_is_valid(diff_data.old_buffer) then
    pcall(vim.api.nvim_buf_delete, diff_data.old_buffer, {force = true})
  end

  -- Close diff window if still open
  if diff_data.diff_window and vim.api.nvim_win_is_valid(diff_data.diff_window) then
    pcall(vim.api.nvim_win_close, diff_data.diff_window, true)
  end

  -- Remove from active diffs
  active_diffs[tab_name] = nil

  -- Log cleanup reason
  require("claudecode.logger").debug("Cleaned up diff state for '" .. tab_name .. "' due to: " .. reason)
end

local function cleanup_all_active_diffs(reason)
  for tab_name, _ in pairs(active_diffs) do
    cleanup_diff_state(tab_name, reason)
  end
end
```

### Phase 4: Diff View Integration

#### 4.1 Native Neovim Diff Creation

```lua
local function create_diff_view(old_buffer, new_buffer, tab_name)
  -- Create new tab for diff
  vim.cmd('tabnew')
  local tab_id = vim.api.nvim_get_current_tabpage()

  -- Set tab name if possible
  pcall(function()
    vim.api.nvim_tabpage_set_var(tab_id, 'claude_diff_name', tab_name)
  end)

  -- Split vertically and set up diff
  vim.cmd('vsplit')

  -- Set old file in left window
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, old_buffer)
  vim.cmd('diffthis')

  -- Set new file in right window
  vim.cmd('wincmd l')
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, new_buffer)
  vim.cmd('diffthis')

  -- Set buffer options for new file
  vim.api.nvim_buf_set_option(new_buffer, 'modifiable', true)
  vim.api.nvim_buf_set_option(new_buffer, 'buflisted', false)
  vim.api.nvim_buf_set_option(new_buffer, 'buftype', '')

  -- Add helpful keymaps
  local keymap_opts = {buffer = new_buffer, silent = true}
  vim.keymap.set('n', '<leader>da', function()
    -- Accept all changes - copy new buffer to old file and save
    local new_content = vim.api.nvim_buf_get_lines(new_buffer, 0, -1, false)
    vim.fn.writefile(new_content, active_diffs[tab_name].old_file_path)
    resolve_diff_as_saved(tab_name, new_buffer)
  end, keymap_opts)

  vim.keymap.set('n', '<leader>dq', function()
    -- Reject changes - close diff
    resolve_diff_as_rejected(tab_name)
  end, keymap_opts)

  return right_win
end
```

### Phase 5: Testing & Validation

#### 5.1 Unit Test Requirements

**Test Cases:**

```lua
-- Test blocking behavior
it("should block until user saves file", function()
  -- Setup mock diff operation
  -- Simulate user save action
  -- Verify FILE_SAVED response with content
end)

it("should block until user closes tab", function()
  -- Setup mock diff operation
  -- Simulate tab close action
  -- Verify DIFF_REJECTED response with tab_name
end)


-- Test concurrent operations
it("should handle multiple concurrent diffs", function()
  -- Start multiple diff operations with different tab_names
  -- Verify each operates independently
  -- Test cleanup of each
end)

-- Test resource cleanup
it("should clean up resources on completion", function()
  -- Start diff operation
  -- Complete operation (save or reject)
  -- Verify all autocmds, buffers, and state cleaned up
end)

-- Test edge cases
it("should handle Neovim shutdown gracefully", function()
  -- Start diff operation
  -- Trigger VimLeavePre event
  -- Verify cleanup occurs
end)

it("should handle invalid file paths", function()
  -- Call openDiff with non-existent old_file_path
  -- Verify proper error response
end)
```

#### 5.2 Integration Test Requirements

**Manual Testing Scenarios:**

1. **Basic Operation**: Open diff, make changes, save file → verify FILE_SAVED response
2. **Rejection**: Open diff, close tab → verify DIFF_REJECTED response
3. **Concurrent Diffs**: Open multiple diffs simultaneously → verify independent operation
4. **Resource Cleanup**: Monitor buffer/autocmd counts during operations
5. **Error Conditions**: Test with invalid paths, permission errors, etc.

#### 5.3 Performance Considerations

**Optimization Requirements:**

- Minimize memory usage for large file diffs
- Efficient cleanup of resources
- Proper handling of concurrent operations without resource conflicts
- Timeout mechanisms to prevent memory leaks

### Phase 6: Error Handling & Edge Cases

#### 6.1 Comprehensive Error Handling

```lua
-- File access errors
local function safe_file_read(file_path)
  local file, err = io.open(file_path, 'r')
  if not file then
    error({
      code = -32000,
      message = "File access error",
      data = "Cannot open file: " .. file_path .. " (" .. (err or "unknown error") .. ")"
    })
  end

  local content = file:read('*all')
  file:close()
  return content
end

-- Buffer creation errors
local function safe_buffer_create(unlisted, scratch)
  local buf = vim.api.nvim_create_buf(unlisted, scratch)
  if buf == 0 then
    error({
      code = -32000,
      message = "Buffer creation failed",
      data = "Could not create buffer - may be out of memory"
    })
  end
  return buf
end
```

#### 6.2 Edge Case Handling

**Neovim Shutdown During Diff:**

- `VimLeavePre` autocmd resolves pending diffs as "shutdown"
- All resources cleaned up before exit
- No orphaned processes or temporary files

**Permission Errors:**

- Graceful handling of read-only files
- Clear error messages for permission issues
- Fallback to read-only diff view when appropriate

**Memory Management:**

- Automatic cleanup of completed diffs
- Buffer deletion on operation completion
- Autocmd cleanup to prevent memory leaks

## Implementation Timeline

### Week 1: Core Architecture

- [ ] Implement enhanced diff.lua module with blocking support
- [ ] Create state management system
- [ ] Add basic autocmd event monitoring

### Week 2: Blocking & Response Format

- [ ] Implement coroutine-based waiting mechanism
- [ ] Add MCP-compliant response formatting
- [ ] Create diff view management functions

### Week 3: Resource Management & Cleanup

- [ ] Implement comprehensive cleanup mechanisms
- [ ] Create autocmd registration/cleanup system

### Week 4: Testing & Validation

- [ ] Write comprehensive unit tests
- [ ] Perform integration testing
- [ ] Test edge cases and error conditions
- [ ] Performance optimization and validation

## Success Criteria

1. **MCP Compliance**: Tool blocks correctly and returns proper MCP content format
2. **Resource Management**: No memory leaks, proper cleanup of all resources
3. **Concurrent Operation**: Multiple diffs can operate simultaneously without conflicts
4. **Error Handling**: Graceful handling of all error conditions with proper JSON-RPC errors
5. **Performance**: Efficient operation with large files and extended blocking periods
6. **User Experience**: Intuitive diff interface with helpful keymaps and clear feedback

## Risk Mitigation

**Coroutine Complexity**: Extensive testing of coroutine behavior in various scenarios
**Resource Leaks**: Automated testing of resource cleanup mechanisms  
**Concurrent Access**: Thread-safety considerations and proper state isolation
**Error Recovery**: Comprehensive error handling with graceful degradation

This plan provides a complete roadmap for implementing a fully MCP-compliant openDiff tool that meets all specification requirements while maintaining robust operation and proper resource management.
