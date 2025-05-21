---@brief [[
--- Claude Code Neovim Integration
--- This plugin integrates Claude Code CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.
---@brief ]]

--- @module 'claudecode'
local M = {}

--- @class ClaudeCode.Version
--- @field major integer Major version number
--- @field minor integer Minor version number
--- @field patch integer Patch version number
--- @field prerelease string|nil Prerelease identifier (e.g., "alpha", "beta")
--- @field string fun(self: ClaudeCode.Version):string Returns the formatted version string

--- The current version of the plugin.
--- @type ClaudeCode.Version
M.version = {
  major = 0,
  minor = 1,
  patch = 0,
  prerelease = "alpha",
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

--- @class ClaudeCode.Config
--- @field port_range {min: integer, max: integer} Port range for WebSocket server.
--- @field auto_start boolean Auto-start WebSocket server on Neovim startup.
--- @field terminal_cmd string|nil Custom terminal command to use when launching Claude.
--- @field log_level "trace"|"debug"|"info"|"warn"|"error" Log level.
--- @field track_selection boolean Enable sending selection updates to Claude.

--- @type ClaudeCode.Config
local default_config = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  log_level = "info",
  track_selection = true,
}

--- @class ClaudeCode.State
--- @field config ClaudeCode.Config The current plugin configuration.
--- @field server table|nil The WebSocket server instance.
--- @field port number|nil The port the server is running on.
--- @field initialized boolean Whether the plugin has been initialized.

--- @type ClaudeCode.State
M.state = {
  config = vim.deepcopy(default_config),
  server = nil,
  port = nil,
  initialized = false,
}

---@alias ClaudeCode.TerminalOpts { \
---  split_side?: "left"|"right", \
---  split_width_percentage?: number, \
---  provider?: "snacks"|"native", \
---  show_native_term_exit_tip?: boolean }
---
---@alias ClaudeCode.SetupOpts { \
---  terminal?: ClaudeCode.TerminalOpts }
---
--- Set up the plugin with user configuration
---@param opts ClaudeCode.SetupOpts|nil Optional configuration table to override defaults.
---@return table The plugin module
function M.setup(opts)
  opts = opts or {}

  -- Separate terminal config from main config
  local terminal_opts = nil
  if opts.terminal then
    terminal_opts = opts.terminal
    opts.terminal = nil -- Remove from main opts to avoid polluting M.state.config
  end

  M.state.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts)

  if terminal_opts then
    local terminal_setup_ok, terminal_module = pcall(require, "claudecode.terminal")
    if terminal_setup_ok then
      terminal_module.setup(terminal_opts)
    else
      vim.notify("Failed to load claudecode.terminal module for setup.", vim.log.levels.ERROR)
    end
  end

  -- TODO: Set up logger with configured log level

  if M.state.config.auto_start then
    M.start(false) -- Suppress notification on auto-start
  end

  M._create_commands()

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
---@param show_startup_notification? boolean Whether to show a notification upon successful startup (defaults to true)
---@return boolean success Whether the operation was successful
---@return number|string port_or_error The WebSocket port if successful, or error message if failed
function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end
  if M.state.server then
    local msg = "Claude Code integration is already running on port " .. tostring(M.state.port)
    vim.notify(msg, vim.log.levels.WARN)
    return false, "Already running"
  end

  local server = require("claudecode.server")
  local success, result = server.start(M.state.config)

  if not success then
    vim.notify("Failed to start Claude Code integration: " .. result, vim.log.levels.ERROR)
    return false, result
  end

  M.state.server = server
  M.state.port = tonumber(result)

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

  if M.state.config.track_selection then
    local selection = require("claudecode.selection")
    selection.enable(server)
  end

  if show_startup_notification then
    vim.notify("Claude Code integration started on port " .. tostring(M.state.port), vim.log.levels.INFO)
  end

  return true, M.state.port
end

--- Stop the Claude Code integration
---@return boolean success Whether the operation was successful
---@return string? error Error message if operation failed
function M.stop()
  if not M.state.server then
    vim.notify("Claude Code integration is not running", vim.log.levels.WARN)
    return false, "Not running"
  end

  local lockfile = require("claudecode.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)

  if not lock_success then
    vim.notify("Failed to remove lock file: " .. lock_error, vim.log.levels.WARN)
    -- Continue with shutdown even if lock file removal fails
  end

  if M.state.config.track_selection then
    local selection = require("claudecode.selection")
    selection.disable()
  end

  local success, error = M.state.server.stop()

  if not success then
    vim.notify("Failed to stop Claude Code integration: " .. error, vim.log.levels.ERROR)
    return false, error
  end

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
    if M.state.server and M.state.port then
      vim.notify("Claude Code integration is running on port " .. tostring(M.state.port), vim.log.levels.INFO)
    else
      vim.notify("Claude Code integration is not running", vim.log.levels.INFO)
    end
  end, {
    desc = "Show Claude Code integration status",
  })

  vim.api.nvim_create_user_command("ClaudeCodeSend", function()
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

return M
