--- Diff provider module for Claude Code Neovim integration.
-- Manages different diff providers (native Neovim and diffview.nvim) with automatic detection and fallback.
-- Enhanced with MCP-compliant blocking operations and state management.
local M = {}

local diff_config = {
  diff_provider = "auto",
  diff_opts = {
    open_in_current_tab = true,
    vertical_split = true,
    auto_close_on_accept = true,
    show_diff_stats = true,
  },
}

-- Global state management for active diffs
local active_diffs = {}
local autocmd_group

--- Get or create the autocmd group
local function get_autocmd_group()
  if not autocmd_group then
    autocmd_group = vim.api.nvim_create_augroup("ClaudeCodeMCPDiff", { clear = true })
  end
  return autocmd_group
end

--- Check if diffview.nvim is available
-- @return boolean true if diffview.nvim is available, false otherwise
function M.is_diffview_available()
  local ok, _ = pcall(require, "diffview")
  return ok
end

--- Get the current effective diff provider
-- @return string The provider being used ("diffview" or "native")
function M.get_current_provider()
  if diff_config.diff_provider == "auto" then
    return M.is_diffview_available() and "diffview" or "native"
  elseif diff_config.diff_provider == "diffview" then
    if M.is_diffview_available() then
      return "diffview"
    else
      vim.notify("diffview.nvim not found, falling back to native diff", vim.log.levels.WARN) -- Explain fallback
      return "native"
    end
  else
    return "native"
  end
end

--- Setup the diff module with configuration
-- @param user_diff_config table|nil User configuration for diff functionality
function M.setup(user_diff_config)
  if user_diff_config then
    diff_config = {
      diff_provider = user_diff_config.diff_provider or diff_config.diff_provider,
      diff_opts = user_diff_config.diff_opts or diff_config.diff_opts,
    }
  end
end

--- Open a diff view between two files
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M.open_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  local provider = M.get_current_provider()

  if provider == "diffview" then
    return M._open_diffview_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  else
    return M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  end
end

--- Create a temporary file with content
-- @param content string The content to write
-- @param filename string Base filename for the temporary file
-- @return string|nil, string|nil The temporary file path and error message
function M._create_temp_file(content, filename)
  local base_dir_cache = vim.fn.stdpath("cache") .. "/claudecode_diffs"
  local mkdir_ok_cache, mkdir_err_cache = pcall(vim.fn.mkdir, base_dir_cache, "p")

  local final_base_dir
  if mkdir_ok_cache then
    final_base_dir = base_dir_cache
  else
    local base_dir_temp = vim.fn.stdpath("cache") .. "/claudecode_diffs_fallback"
    local mkdir_ok_temp, mkdir_err_temp = pcall(vim.fn.mkdir, base_dir_temp, "p")
    if not mkdir_ok_temp then
      local err_to_report = mkdir_err_temp or mkdir_err_cache or "unknown error creating base temp dir"
      return nil, "Failed to create base temporary directory: " .. tostring(err_to_report)
    end
    final_base_dir = base_dir_temp
  end

  local session_id_base = vim.fn.fnamemodify(vim.fn.tempname(), ":t")
    .. "_"
    .. tostring(os.time())
    .. "_"
    .. tostring(math.random(1000, 9999))
  local session_id = session_id_base:gsub("[^A-Za-z0-9_-]", "")
  if session_id == "" then -- Fallback if all characters were problematic, ensuring a directory can be made.
    session_id = "claudecode_session"
  end

  local tmp_session_dir = final_base_dir .. "/" .. session_id
  local mkdir_session_ok, mkdir_session_err = pcall(vim.fn.mkdir, tmp_session_dir, "p")
  if not mkdir_session_ok then
    return nil, "Failed to create temporary session directory: " .. tostring(mkdir_session_err)
  end

  local tmp_file = tmp_session_dir .. "/" .. filename
  local file = io.open(tmp_file, "w")
  if not file then
    return nil, "Failed to create temporary file: " .. tmp_file
  end

  file:write(content)
  file:close()

  return tmp_file, nil
end

--- Clean up temporary files and directories
-- @param tmp_file string Path to the temporary file to clean up
function M._cleanup_temp_file(tmp_file)
  if tmp_file and vim.fn.filereadable(tmp_file) == 1 then
    local tmp_dir = vim.fn.fnamemodify(tmp_file, ":h")
    if vim.fs and type(vim.fs.remove) == "function" then
      local ok_file, err_file = pcall(vim.fs.remove, tmp_file)
      if not ok_file then
        vim.notify(
          "ClaudeCode: Error removing temp file " .. tmp_file .. ": " .. tostring(err_file),
          vim.log.levels.WARN
        )
      end

      local ok_dir, err_dir = pcall(vim.fs.remove, tmp_dir)
      if not ok_dir then
        vim.notify(
          "ClaudeCode: Error removing temp directory " .. tmp_dir .. ": " .. tostring(err_dir),
          vim.log.levels.INFO
        )
      end
    else
      local reason = "vim.fs.remove is not a function"
      if not vim.fs then
        reason = "vim.fs is nil"
      end
      vim.notify(
        "ClaudeCode: Cannot perform standard cleanup: "
          .. reason
          .. ". Affected file: "
          .. tmp_file
          .. ". Please check your Neovim setup or report this issue.",
        vim.log.levels.ERROR
      )
      -- Fallback to os.remove for the file.
      local os_ok, os_err = pcall(os.remove, tmp_file)
      if not os_ok then
        vim.notify(
          "ClaudeCode: Fallback os.remove also failed for file " .. tmp_file .. ": " .. tostring(os_err),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

--- Open diff using native Neovim functionality
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  local new_filename = vim.fn.fnamemodify(new_file_path, ":t") .. ".new"
  local tmp_file, err = M._create_temp_file(new_file_contents, new_filename)
  if not tmp_file then
    return { provider = "native", tab_name = tab_name, success = false, error = err }
  end

  if diff_config and diff_config.diff_opts and diff_config.diff_opts.open_in_current_tab then
    local original_buf = vim.api.nvim_get_current_buf()
    local _ = vim.api.nvim_buf_get_name(original_buf) -- Storing original buffer name, though not currently used, might be useful for future enhancements.
    vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
  else
    vim.cmd("tabnew")
    vim.api.nvim_buf_set_name(0, tab_name)
    vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
  end

  vim.cmd("diffthis")

  if diff_config and diff_config.diff_opts and diff_config.diff_opts.vertical_split then
    vim.cmd("vertical split")
  else
    vim.cmd("split")
  end

  vim.cmd("edit " .. vim.fn.fnameescape(tmp_file))
  vim.api.nvim_buf_set_name(0, new_file_path .. " (New)")

  local new_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = new_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = new_buf })

  vim.cmd("diffthis")

  local cleanup_group = vim.api.nvim_create_augroup("ClaudeCodeDiffCleanup", { clear = false })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = cleanup_group,
    buffer = new_buf,
    callback = function()
      M._cleanup_temp_file(tmp_file)
    end,
    once = true,
  })

  return {
    provider = "native",
    tab_name = tab_name,
    success = true,
    temp_file = tmp_file,
  }
end

--- Open diff using diffview.nvim (placeholder for now)
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M._open_diffview_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  -- TODO: Implement full diffview.nvim integration (Phase 4)
  -- For now, fall back to native implementation. This notification informs the user about the current behavior.
  vim.notify("diffview.nvim integration not yet implemented, using native diff", vim.log.levels.INFO)
  return M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
end

--- Create a scratch buffer for new content
-- @param content string The content to put in the buffer
-- @param filename string The filename for the buffer
-- @return number The buffer ID
function M._create_new_content_buffer(content, filename)
  local buf = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
  if buf == 0 then
    error({
      code = -32000,
      message = "Buffer creation failed",
      data = "Could not create buffer - may be out of memory",
    })
  end

  vim.api.nvim_buf_set_name(buf, filename)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  return buf
end

--- Safe file reading with error handling
-- @param file_path string Path to the file to read
-- @return string The file content
function M._safe_file_read(file_path)
  local file, err = io.open(file_path, "r")
  if not file then
    error({
      code = -32000,
      message = "File access error",
      data = "Cannot open file: " .. file_path .. " (" .. (err or "unknown error") .. ")",
    })
  end

  local content = file:read("*all")
  file:close()
  return content
end

--- Register diff state for tracking
-- @param tab_name string Unique identifier for the diff
-- @param diff_data table Diff state data
function M._register_diff_state(tab_name, diff_data)
  active_diffs[tab_name] = diff_data
end

--- Find diff by buffer ID
-- @param buffer_id number Buffer ID to search for
-- @return string|nil The tab_name if found
function M._find_diff_by_buffer(buffer_id)
  for tab_name, diff_data in pairs(active_diffs) do
    if diff_data.new_buffer == buffer_id or diff_data.old_buffer == buffer_id then
      return tab_name
    end
  end
  return nil
end

--- Resolve diff as saved (user accepted changes)
-- @param tab_name string The diff identifier
-- @param buffer_id number The buffer that was saved
function M._resolve_diff_as_saved(tab_name, buffer_id)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= "pending" then
    return
  end

  -- Get final file contents
  local final_content = table.concat(vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false), "\n")

  -- Create MCP-compliant response
  local result = {
    content = {
      { type = "text", text = "FILE_SAVED" },
      { type = "text", text = final_content },
    },
  }

  diff_data.status = "saved"
  diff_data.result_content = result

  -- Resume the coroutine with the result (for deferred response system)
  if diff_data.resolution_callback then
    require("claudecode.logger").debug("diff", "Resuming coroutine for saved diff", tab_name)
    -- The resolution_callback is actually coroutine.resume(co, result)
    diff_data.resolution_callback(result)
  else
    require("claudecode.logger").debug("diff", "No resolution callback found for saved diff", tab_name)
  end

  -- Write the accepted changes to the actual file and reload any open buffers
  M._apply_accepted_changes(diff_data, final_content)

  -- Clean up diff state and resources
  M._cleanup_diff_state(tab_name, "file saved")
end

--- Apply accepted changes to the original file and reload open buffers
-- @param diff_data table The diff state data
-- @param final_content string The final content to write
function M._apply_accepted_changes(diff_data, final_content)
  local old_file_path = diff_data.old_file_path
  if not old_file_path then
    require("claudecode.logger").error("diff", "No old_file_path found in diff_data")
    return
  end

  require("claudecode.logger").debug("diff", "Writing accepted changes to file:", old_file_path)

  -- Write the content to the actual file
  local lines = vim.split(final_content, "\n")
  local success, err = pcall(vim.fn.writefile, lines, old_file_path)

  if not success then
    require("claudecode.logger").error("diff", "Failed to write file:", old_file_path, "error:", err)
    return
  end

  require("claudecode.logger").debug("diff", "Successfully wrote changes to", old_file_path)

  -- Find and reload any open buffers for this file
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == old_file_path then
        require("claudecode.logger").debug("diff", "Reloading buffer", buf, "for file:", old_file_path)
        -- Use :edit to reload the buffer
        -- We need to execute this in the context of the buffer
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit")
        end)
        require("claudecode.logger").debug("diff", "Successfully reloaded buffer", buf)
      end
    end
  end
end

--- Resolve diff as rejected (user closed/rejected)
-- @param tab_name string The diff identifier
function M._resolve_diff_as_rejected(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= "pending" then
    return
  end

  -- Create MCP-compliant response
  local result = {
    content = {
      { type = "text", text = "DIFF_REJECTED" },
      { type = "text", text = tab_name },
    },
  }

  diff_data.status = "rejected"
  diff_data.result_content = result

  -- Resume the coroutine with the result (for deferred response system)
  if diff_data.resolution_callback then
    require("claudecode.logger").debug("diff", "Resuming coroutine for rejected diff", tab_name)
    -- The resolution_callback is actually coroutine.resume(co, result)
    diff_data.resolution_callback(result)
  else
    require("claudecode.logger").debug("diff", "No resolution callback found for rejected diff", tab_name)
  end

  -- Clean up diff state and resources
  M._cleanup_diff_state(tab_name, "diff rejected")
end

--- Register autocmds for a specific diff
-- @param tab_name string The diff identifier
-- @param new_buffer number New file buffer ID
-- @param old_buffer number Old file buffer ID
-- @return table List of autocmd IDs
function M._register_diff_autocmds(tab_name, new_buffer, old_buffer)
  local autocmd_ids = {}

  -- Save event monitoring for new buffer (BufWritePost)
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWritePost", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      require("claudecode.logger").debug("diff", "BufWritePost triggered - accepting diff changes for", tab_name)
      M._resolve_diff_as_saved(tab_name, new_buffer)
    end,
  })

  -- Also handle :w command directly (BufWriteCmd) for immediate acceptance
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      require("claudecode.logger").debug("diff", "BufWriteCmd (:w) triggered - accepting diff changes for", tab_name)
      M._resolve_diff_as_saved(tab_name, new_buffer)
    end,
  })

  -- Buffer deletion monitoring for rejection (multiple events to catch all deletion methods)

  -- BufDelete: When buffer is deleted with :bdelete, :bwipeout, etc.
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufDelete", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      require("claudecode.logger").debug("diff", "BufDelete triggered for new buffer", new_buffer, "tab:", tab_name)
      M._resolve_diff_as_rejected(tab_name)
    end,
  })

  -- BufUnload: When buffer is unloaded (covers more scenarios)
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufUnload", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      require("claudecode.logger").debug("diff", "BufUnload triggered for new buffer", new_buffer, "tab:", tab_name)
      M._resolve_diff_as_rejected(tab_name)
    end,
  })

  -- BufWipeout: When buffer is wiped out completely
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd("BufWipeout", {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      require("claudecode.logger").debug("diff", "BufWipeout triggered for new buffer", new_buffer, "tab:", tab_name)
      M._resolve_diff_as_rejected(tab_name)
    end,
  })

  -- Note: We intentionally do NOT monitor old_buffer for deletion
  -- because it's the actual file buffer and shouldn't trigger diff rejection

  return autocmd_ids
end

--- Create diff view with native Neovim
-- @param old_buffer number Old file buffer ID
-- @param new_buffer number New file buffer ID
-- @param tab_name string The diff identifier
-- @return number The window ID of the diff view
function M._create_diff_view(old_buffer, new_buffer, tab_name)
  -- Create new tab for diff
  require("claudecode.logger").debug("diff", "Creating new tab for diff view")
  vim.cmd("tabnew")
  local tab_id = vim.api.nvim_get_current_tabpage()
  require("claudecode.logger").debug("diff", "Created tab", tab_id, "for diff")

  -- Set tab name if possible
  pcall(function()
    vim.api.nvim_tabpage_set_var(tab_id, "claude_diff_name", tab_name)
  end)

  -- Split vertically and set up diff
  require("claudecode.logger").debug("diff", "Creating vertical split")

  -- Start with old buffer in current window
  vim.api.nvim_win_set_buf(0, old_buffer)
  vim.cmd("diffthis")
  local left_win = vim.api.nvim_get_current_win()
  require("claudecode.logger").debug("diff", "Set old buffer", old_buffer, "in left window", left_win)

  -- Create vertical split with new buffer
  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, new_buffer)
  vim.cmd("diffthis")
  require("claudecode.logger").debug("diff", "Set new buffer", new_buffer, "in right window", right_win)

  require("claudecode.logger").debug(
    "diff",
    "Diff view setup complete - left window:",
    left_win,
    "right window:",
    right_win
  )

  -- Set buffer options for new file (keep consistent with setup)
  vim.api.nvim_buf_set_option(new_buffer, "modifiable", true)
  vim.api.nvim_buf_set_option(new_buffer, "buflisted", false)
  -- Note: Keep buftype as "acwrite" from setup, don't change it here

  -- Add helpful keymaps
  local keymap_opts = { buffer = new_buffer, silent = true }
  vim.keymap.set("n", "<leader>da", function()
    -- Accept all changes - copy new buffer to old file and save
    local new_content = vim.api.nvim_buf_get_lines(new_buffer, 0, -1, false)
    vim.fn.writefile(new_content, active_diffs[tab_name].old_file_path)
    M._resolve_diff_as_saved(tab_name, new_buffer)
  end, keymap_opts)

  vim.keymap.set("n", "<leader>dq", function()
    -- Reject changes - close diff
    M._resolve_diff_as_rejected(tab_name)
  end, keymap_opts)

  return right_win
end

--- Clean up diff state and resources
-- @param tab_name string The diff identifier
-- @param reason string Reason for cleanup
function M._cleanup_diff_state(tab_name, reason)
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
    pcall(vim.api.nvim_buf_delete, diff_data.new_buffer, { force = true })
  end

  if diff_data.old_buffer and vim.api.nvim_buf_is_valid(diff_data.old_buffer) then
    pcall(vim.api.nvim_buf_delete, diff_data.old_buffer, { force = true })
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

--- Clean up all active diffs
-- @param reason string Reason for cleanup
function M._cleanup_all_active_diffs(reason)
  for tab_name, _ in pairs(active_diffs) do
    M._cleanup_diff_state(tab_name, reason)
  end
end

--- Set up blocking diff operation with simpler approach
-- @param params table Parameters for the diff
-- @param resolution_callback function Callback to call when diff resolves
function M._setup_blocking_diff(params, resolution_callback)
  local tab_name = params.tab_name
  require("claudecode.logger").debug("diff", "Setup step 1: Finding/creating old buffer for", params.old_file_path)

  -- Step 1: Create a fresh buffer for the original file content
  local old_file_exists = vim.fn.filereadable(params.old_file_path) == 1

  if not old_file_exists then
    error({
      code = -32602,
      message = "Invalid params",
      data = "Original file does not exist: " .. params.old_file_path,
    })
  end

  -- Always create a fresh buffer for old content to avoid conflicts
  local old_buffer = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
  if old_buffer == 0 then
    error({
      code = -32000,
      message = "Buffer creation failed",
      data = "Could not create old content buffer",
    })
  end

  -- Read original file content directly
  local old_content = M._safe_file_read(params.old_file_path)
  local old_unique_name = tab_name .. " (original)"
  vim.api.nvim_buf_set_name(old_buffer, old_unique_name)
  vim.api.nvim_buf_set_lines(old_buffer, 0, -1, false, vim.split(old_content, "\n"))

  -- Set buffer options for old content buffer
  vim.api.nvim_buf_set_option(old_buffer, "buftype", "nofile")
  vim.api.nvim_buf_set_option(old_buffer, "modifiable", false) -- Read-only

  -- Step 2: Create scratch buffer for new content
  require("claudecode.logger").debug("diff", "Setup step 2: Creating new content buffer")
  local new_buffer = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
  if new_buffer == 0 then
    error({
      code = -32000,
      message = "Buffer creation failed",
      data = "Could not create new content buffer",
    })
  end

  local new_unique_name = tab_name .. " (proposed)"
  vim.api.nvim_buf_set_name(new_buffer, new_unique_name)
  vim.api.nvim_buf_set_lines(new_buffer, 0, -1, false, vim.split(params.new_file_contents, "\n"))

  -- Set buffer options for the new content buffer
  vim.api.nvim_buf_set_option(new_buffer, "buftype", "acwrite") -- Allows saving but stays as scratch-like
  vim.api.nvim_buf_set_option(new_buffer, "modifiable", true)

  -- Step 3: Set up diff view
  require("claudecode.logger").debug("diff", "Setup step 3: Creating diff view")
  local diff_window = M._create_diff_view(old_buffer, new_buffer, tab_name)

  -- Step 4: Register autocmds for user interaction monitoring
  require("claudecode.logger").debug("diff", "Setup step 4: Registering autocmds")
  local autocmd_ids = M._register_diff_autocmds(tab_name, new_buffer, old_buffer)

  -- Step 5: Store diff state
  require("claudecode.logger").debug("diff", "Setup step 5: Storing diff state")
  M._register_diff_state(tab_name, {
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
  })
  require("claudecode.logger").debug("diff", "Setup completed successfully for", tab_name)
end

--- Blocking diff operation for MCP compliance
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table MCP-compliant response with content array
function M.open_diff_blocking(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Check for existing diff with same tab_name
  if active_diffs[tab_name] then
    -- Resolve the existing diff as rejected before replacing
    M._resolve_diff_as_rejected(tab_name)
  end

  -- Set up blocking diff operation
  local co = coroutine.running()
  if not co then
    error({
      code = -32000,
      message = "Internal server error",
      data = "openDiff must run in coroutine context",
    })
  end

  -- Initialize diff state and monitoring
  require("claudecode.logger").debug("diff", "Starting diff setup for tab_name:", tab_name)

  local success, err = pcall(M._setup_blocking_diff, {
    old_file_path = old_file_path,
    new_file_path = new_file_path,
    new_file_contents = new_file_contents,
    tab_name = tab_name,
  }, function(result)
    -- Resume the coroutine with the result
    require("claudecode.logger").debug("diff", "Resolution callback called for coroutine:", tostring(co))
    local resume_success, resume_result = coroutine.resume(co, result)
    if resume_success then
      -- Coroutine completed successfully - send the response using the global sender
      require("claudecode.logger").debug(
        "diff",
        "Coroutine completed successfully with result:",
        vim.inspect(resume_result)
      )

      -- Use the global response sender to avoid module reloading issues
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        require("claudecode.logger").debug("diff", "Calling global response sender for coroutine:", co_key)
        _G.claude_deferred_responses[co_key](resume_result)
        -- Clean up
        _G.claude_deferred_responses[co_key] = nil
      else
        require("claudecode.logger").error("diff", "No global response sender found for coroutine:", co_key)
      end
    else
      -- Coroutine failed - send error response
      require("claudecode.logger").error("diff", "Coroutine failed:", tostring(resume_result))
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key]({
          error = {
            code = -32603,
            message = "Internal error",
            data = "Coroutine failed: " .. tostring(resume_result),
          },
        })
        -- Clean up
        _G.claude_deferred_responses[co_key] = nil
      end
    end
  end)

  if not success then
    require("claudecode.logger").error("diff", "Diff setup failed for", tab_name, "error:", vim.inspect(err))
    -- If the error is already structured, propagate it directly
    if type(err) == "table" and err.code then
      error(err)
    else
      error({
        code = -32000,
        message = "Error setting up diff",
        data = tostring(err),
      })
    end
  end

  require("claudecode.logger").debug(
    "diff",
    "Diff setup completed successfully for",
    tab_name,
    "- about to yield and wait for user action"
  )

  -- Yield and wait indefinitely for user interaction - the resolve functions will resume us
  require("claudecode.logger").debug("diff", "About to yield and wait for user action")
  local user_action_result = coroutine.yield()
  require("claudecode.logger").debug("diff", "User interaction detected, got result:", vim.inspect(user_action_result))

  -- Return the result directly - this will be sent by the deferred response system
  return user_action_result
end

-- Set up global autocmds for shutdown handling
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = get_autocmd_group(),
  callback = function()
    M._cleanup_all_active_diffs("shutdown")
  end,
})

return M
