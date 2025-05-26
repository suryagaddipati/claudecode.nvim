--- Diff provider module for Claude Code Neovim integration.
-- Manages different diff providers (native Neovim and diffview.nvim) with automatic detection and fallback.
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
        vim.notify("ClaudeCode: Error removing temp file " .. tmp_file .. ": " .. tostring(err_file), vim.log.levels.WARN)
      end

      local ok_dir, err_dir = pcall(vim.fs.remove, tmp_dir)
      if not ok_dir then
        vim.notify("ClaudeCode: Error removing temp directory " .. tmp_dir .. ": " .. tostring(err_dir), vim.log.levels.INFO)
      end
    else
      local reason = "vim.fs.remove is not a function"
      if not vim.fs then
        reason = "vim.fs is nil"
      end
      vim.notify(
        "ClaudeCode: Cannot perform standard cleanup: " .. reason .. ". Affected file: " .. tmp_file ..
        ". Please check your Neovim setup or report this issue.",
        vim.log.levels.ERROR
      )
      -- Fallback to os.remove for the file.
      local os_ok, os_err = pcall(os.remove, tmp_file)
      if not os_ok then
         vim.notify("ClaudeCode: Fallback os.remove also failed for file " .. tmp_file .. ": " .. tostring(os_err), vim.log.levels.ERROR)
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

return M
