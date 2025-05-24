--- Diff provider module for Claude Code Neovim integration.
-- Manages different diff providers (native Neovim and diffview.nvim) with automatic detection and fallback.
local M = {}

-- Internal state with safe defaults
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
      vim.notify("diffview.nvim not found, falling back to native diff", vim.log.levels.WARN)
      return "native"
    end
  else
    return "native"
  end
end

--- Setup the diff module with configuration
-- @param user_diff_config table|nil User configuration for diff functionality
function M.setup(user_diff_config)
  -- Simple setup without config module dependency for now
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
  local tmp_dir = vim.fn.tempname() .. "_claudecode_diff"
  local ok, err = pcall(vim.fn.mkdir, tmp_dir, "p")
  if not ok then
    return nil, "Failed to create temporary directory: " .. tostring(err)
  end

  local tmp_file = tmp_dir .. "/" .. filename
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
    vim.fn.delete(tmp_file)
    vim.fn.delete(tmp_dir, "d")
  end
end

--- Open diff using native Neovim functionality
-- @param old_file_path string Path to the original file
-- @param new_file_path string Path to the new file (used for naming)
-- @param new_file_contents string Contents of the new file
-- @param tab_name string Name for the diff tab/view
-- @return table Result with provider, tab_name, and success status
function M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Create temporary file for new content
  local new_filename = vim.fn.fnamemodify(new_file_path, ":t") .. ".new"
  local tmp_file, err = M._create_temp_file(new_file_contents, new_filename)
  if not tmp_file then
    return { provider = "native", tab_name = tab_name, success = false, error = err }
  end

  -- Choose whether to open in current tab or new tab based on configuration
  if diff_config and diff_config.diff_opts and diff_config.diff_opts.open_in_current_tab then
    -- Save current buffer info for restoration later if needed
    local original_buf = vim.api.nvim_get_current_buf()
    local _ = vim.api.nvim_buf_get_name(original_buf) -- unused for now but may be needed later

    -- Open the original file in the current buffer
    vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
  else
    -- Create a new tab for the diff (old behavior)
    vim.cmd("tabnew")

    -- Set the tab name
    vim.api.nvim_buf_set_name(0, tab_name)

    -- Open the original file
    vim.cmd("edit " .. vim.fn.fnameescape(old_file_path))
  end

  -- Enable diff mode
  vim.cmd("diffthis")

  -- Create split based on configuration
  if diff_config and diff_config.diff_opts and diff_config.diff_opts.vertical_split then
    vim.cmd("vertical split")
  else
    vim.cmd("split")
  end

  -- Open the temporary file with new content
  vim.cmd("edit " .. vim.fn.fnameescape(tmp_file))
  vim.api.nvim_buf_set_name(0, new_file_path .. " (New)")

  -- Configure the new content buffer
  local new_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = new_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = new_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = new_buf })

  -- Enable diff mode
  vim.cmd("diffthis")

  -- Set up buffer-local keymaps for diff navigation and exit (only in current tab mode)
  if diff_config and diff_config.diff_opts and diff_config.diff_opts.open_in_current_tab then
    local function setup_diff_keymaps()
      -- Map <leader>dq to quit diff mode
      vim.keymap.set("n", "<leader>dq", function()
        vim.cmd("diffoff!")
        vim.cmd("wincmd o") -- Close other windows (the diff split)
        M._cleanup_temp_file(tmp_file)
        vim.notify("Diff mode exited", vim.log.levels.INFO)
      end, { buffer = true, desc = "Exit diff mode" })

      -- Map <leader>da to accept all changes (replace current buffer with new content)
      vim.keymap.set("n", "<leader>da", function()
        vim.cmd("diffoff!")
        vim.cmd("wincmd o") -- Close other windows
        -- Load the new content into the current buffer
        local lines = vim.split(new_file_contents, "\n")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        M._cleanup_temp_file(tmp_file)
        vim.notify("All changes accepted", vim.log.levels.INFO)
      end, { buffer = true, desc = "Accept all changes" })
    end

    setup_diff_keymaps()
  end

  -- Set up autocmd for cleanup when buffers are deleted
  local cleanup_group = vim.api.nvim_create_augroup("ClaudeCodeDiffCleanup", { clear = false })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = cleanup_group,
    buffer = new_buf,
    callback = function()
      M._cleanup_temp_file(tmp_file)
    end,
    once = true,
  })

  -- Show diff info with helpful keymaps
  vim.defer_fn(function()
    local message
    if diff_config and diff_config.diff_opts and diff_config.diff_opts.open_in_current_tab then
      message =
        string.format("Diff: %s | Use ]c/[c to navigate, <leader>da to accept all, <leader>dq to exit", tab_name)
    else
      message = string.format("Diff: %s | Use ]c/[c to navigate changes, close tab when done", tab_name)
    end
    vim.notify(message, vim.log.levels.INFO)
  end, 100)

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
  -- For now, fall back to native implementation
  -- This will be properly implemented in Phase 4
  vim.notify("diffview.nvim integration not yet implemented, using native diff", vim.log.levels.INFO)
  return M._open_native_diff(old_file_path, new_file_path, new_file_contents, tab_name)
end

return M
