---@brief [[
--- Claude Code Neovim Integration
--- This plugin integrates Claude Code CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.
---@brief ]]

--- @module 'claudecode'
local M = {}

--- The current version of the plugin
M.version = {
  major = 0,
  minor = 1,
  patch = 0,
  prerelease = "alpha",
  -- Return formatted version string
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

-- Default configuration
local default_config = {
  -- Port range for WebSocket server
  port_range = { min = 10000, max = 65535 },

  -- Auto-start WebSocket server on Neovim startup
  auto_start = false,

  -- Custom terminal command to use when launching Claude
  terminal_cmd = nil,

  -- Log level (trace, debug, info, warn, error)
  log_level = "info",

  -- Enable sending selection updates to Claude
  track_selection = true,
}

-- Plugin state
M.state = {
  config = vim.deepcopy(default_config),
  server = nil,
  port = nil,
  initialized = false,
}

--- Set up the plugin with user configuration
---@param opts table|nil Optional configuration table to override defaults
---@return table The plugin module
function M.setup(opts)
  -- Merge user config with defaults
  opts = opts or {}
  M.state.config = vim.tbl_deep_extend("force", default_config, opts)

  -- Initialize the logger
  -- TODO: Set up logger with configured log level

  -- Auto-start if configured
  if M.state.config.auto_start then
    M.start()
  end

  -- Set up commands
  M._create_commands()

  -- Set up auto-shutdown on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClaudeCodeShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      end
    end,
    desc = "Automatically stop Claude Code integration when exiting Neovim",
  })

  M.state.initialized = true
  return M
end

--- Start the Claude Code integration
---@return boolean success Whether the operation was successful
---@return number|string port_or_error The WebSocket port if successful, or error message if failed
function M.start()
  if M.state.server then
    -- Already running
    local msg = "Claude Code integration is already running on port " .. tostring(M.state.port)
    vim.notify(msg, vim.log.levels.WARN)
    return false, "Already running"
  end

  -- Initialize the WebSocket server
  local server = require("claudecode.server")
  local success, result = server.start(M.state.config)

  if not success then
    vim.notify("Failed to start Claude Code integration: " .. result, vim.log.levels.ERROR)
    return false, result
  end

  M.state.server = server
  M.state.port = result

  -- Create lock file
  local lockfile = require("claudecode.lockfile")
  local lock_success, lock_result = lockfile.create(M.state.port)

  if not lock_success then
    -- Stop server if lock file creation fails
    server.stop()
    M.state.server = nil
    M.state.port = nil

    vim.notify("Failed to create lock file: " .. lock_result, vim.log.levels.ERROR)
    return false, lock_result
  end

  -- Set up selection tracking
  if M.state.config.track_selection then
    local selection = require("claudecode.selection")
    selection.enable(server)
  end

  vim.notify("Claude Code integration started on port " .. tostring(M.state.port), vim.log.levels.INFO)

  -- Return the port number as a success indicator
  return true, M.state.port
end

--- Stop the Claude Code integration
---@return boolean success Whether the operation was successful
---@return string? error Error message if operation failed
function M.stop()
  if not M.state.server then
    -- Not running
    vim.notify("Claude Code integration is not running", vim.log.levels.WARN)
    return false, "Not running"
  end

  -- Remove lock file
  local lockfile = require("claudecode.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)

  if not lock_success then
    vim.notify("Failed to remove lock file: " .. lock_error, vim.log.levels.WARN)
    -- Continue with shutdown even if lock file removal fails
  end

  -- Disable selection tracking
  if M.state.config.track_selection then
    local selection = require("claudecode.selection")
    selection.disable()
  end

  -- Stop the WebSocket server
  local success, error = M.state.server.stop()

  if not success then
    vim.notify("Failed to stop Claude Code integration: " .. error, vim.log.levels.ERROR)
    return false, error
  end

  -- Reset state
  M.state.server = nil
  M.state.port = nil

  vim.notify("Claude Code integration stopped", vim.log.levels.INFO)

  return true
end

--- Set up user commands
---@private
function M._create_commands()
  vim.api.nvim_create_user_command("ClaudeCodeStart", function()
    M.start()
  end, {
    desc = "Start Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStop", function()
    M.stop()
  end, {
    desc = "Stop Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStatus", function()
    -- Show status
    if M.state.server and M.state.port then
      vim.notify("Claude Code integration is running on port " .. tostring(M.state.port), vim.log.levels.INFO)
    else
      vim.notify("Claude Code integration is not running", vim.log.levels.INFO)
    end
  end, {
    desc = "Show Claude Code integration status",
  })

  vim.api.nvim_create_user_command("ClaudeCodeSend", function()
    -- Send current selection to Claude
    if not M.state.server then
      vim.notify("Claude Code integration is not running", vim.log.levels.ERROR)
      return
    end

    local selection = require("claudecode.selection")
    selection.send_current_selection()
  end, {
    desc = "Send current selection to Claude Code",
  })
end

--- Get version information
---@return table Version information
function M.get_version()
  return {
    version = M.version:string(),
    major = M.version.major,
    minor = M.version.minor,
    patch = M.version.patch,
    prerelease = M.version.prerelease,
  }
end

-- Return the module
return M
