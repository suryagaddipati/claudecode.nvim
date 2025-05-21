--- Module to manage a dedicated vertical split terminal for Claude Code using Snacks.nvim.
-- @module claudecode.terminal
-- @plugin snacks.nvim

local M = {}
local Snacks = require("snacks")
local claudecode_config_module = require("claudecode.config")

-- Default configuration for the terminal module itself
local term_module_config = {
  split_side = "right", -- 'left' or 'right'
  split_width_percentage = 0.30, -- e.g., 0.30 for 30%
}

--- State to keep track of the managed Claude terminal instance (from Snacks).
-- @type table|nil #snacks_terminal_instance The Snacks terminal instance, or nil if not active.
local managed_snacks_terminal = nil

-- Private helper functions

--- Retrieves the current merged ClaudeCode configuration.
-- @local
-- @return table The current configuration.
local function get_current_claudecode_config()
  local user_conf = vim.g.claudecode_user_config or {}
  return claudecode_config_module.apply(user_conf)
end

--- Determines the command to run in the terminal.
-- Uses the `terminal_cmd` from the main configuration, or defaults to "claude".
-- @local
-- @return string The command to execute.
local function get_claude_command()
  local current_main_config = get_current_claudecode_config()
  local cmd_from_config = current_main_config.terminal_cmd
  if not cmd_from_config or cmd_from_config == "" then
    return "claude" -- Default if not configured
  end
  return cmd_from_config
end

-- Public API

--- Configures the terminal module.
-- Merges user-provided terminal configuration with defaults.
-- @param user_term_config table (optional) Configuration options for the terminal.
-- @field user_term_config.split_side string 'left' or 'right' (default: 'right').
-- @field user_term_config.split_width_percentage number Percentage of screen width (0.0 to 1.0, default: 0.30).
function M.setup(user_term_config)
  if type(user_term_config) ~= "table" then
    vim.notify("claudecode.terminal.setup expects a table", vim.log.levels.WARN)
    user_term_config = {}
  end
  for k, v in pairs(user_term_config) do
    if term_module_config[k] ~= nil then
      if k == "split_side" and (v == "left" or v == "right") then
        term_module_config[k] = v
      elseif k == "split_width_percentage" and type(v) == "number" and v > 0 and v < 1 then
        term_module_config[k] = v
      else
        vim.notify("claudecode.terminal.setup: Invalid value for " .. k, vim.log.levels.WARN)
      end
    else
      vim.notify("claudecode.terminal.setup: Unknown configuration key: " .. k, vim.log.levels.WARN)
    end
  end
end

--- Builds the options table for Snacks.terminal.
-- This function merges the module's current terminal configuration
-- with any runtime overrides provided specifically for an open/toggle action.
-- @local
-- @param opts_override table (optional) Overrides for terminal appearance (split_side, split_width_percentage).
-- @return table The options table for Snacks.
local function build_snacks_opts(opts_override)
  -- Start with a deep copy of the module config
  local effective_term_config = vim.deepcopy(term_module_config)
  -- Process valid overrides if provided
  if type(opts_override) == "table" then
    -- Validation map for allowed values
    local validators = {
      split_side = function(val)
        return val == "left" or val == "right"
      end,
      split_width_percentage = function(val)
        return type(val) == "number" and val > 0 and val < 1
      end,
    }
    -- Apply valid overrides
    for key, val in pairs(opts_override) do
      if effective_term_config[key] ~= nil and validators[key] and validators[key](val) then
        effective_term_config[key] = val
      end
    end
  end
  -- Return the formatted Snacks options
  return {
    interactive = true, -- for auto_close and start_insert
    enter = true, -- focus the terminal when opened
    win = {
      position = effective_term_config.split_side,
      width = effective_term_config.split_width_percentage, -- snacks.win uses <1 for relative width
      height = 0, -- 0 for full height in snacks.win
      relative = "editor",
      on_close = function(self) -- self here is the snacks.win instance
        if managed_snacks_terminal and managed_snacks_terminal.winid == self.winid then
          managed_snacks_terminal = nil
        end
      end,
    },
  }
end

--- Opens or focuses the Claude terminal.
-- If a managed terminal already exists and is valid, it will be focused and `startinsert` will be attempted.
-- Otherwise, a new terminal is opened using the command from `get_claude_command()`.
-- @param opts_override table (optional) Overrides for terminal appearance (e.g., split_side, split_width_percentage).
-- These are passed to `build_snacks_opts` if a new terminal is opened.
function M.open(opts_override)
  if not Snacks or not Snacks.terminal then
    vim.notify("Snacks.nvim or Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end
  local claude_command = get_claude_command()
  -- This check is technically redundant due to the default in get_claude_command,
  -- but kept for robustness.
  if not claude_command then -- Should not happen due to default in get_claude_command
    vim.notify("Claude terminal command cannot be determined.", vim.log.levels.ERROR)
    return
  end
  -- Snacks.terminal.get can find an existing terminal by cmd and other factors.
  -- We use a more direct check for our single managed terminal for simplicity here.
  if managed_snacks_terminal and managed_snacks_terminal:valid() then
    managed_snacks_terminal:focus()
    -- Check if it's a terminal type buffer before startinsert
    local term_buf_id = managed_snacks_terminal.buf
    if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
      vim.api.nvim_win_call(managed_snacks_terminal.winid, function()
        vim.cmd("startinsert")
      end)
    end
    return
  end
  local snacks_opts = build_snacks_opts(opts_override)
  local term_instance = Snacks.terminal.open(claude_command, snacks_opts)
  if term_instance and term_instance:valid() then
    managed_snacks_terminal = term_instance
  else
    vim.notify("Failed to open Claude terminal using Snacks.", vim.log.levels.ERROR)
    managed_snacks_terminal = nil -- Ensure it's nil if open failed
  end
end

--- Closes the managed Claude terminal if it's open and valid.
function M.close()
  if not Snacks or not Snacks.terminal then
    vim.notify("Snacks.nvim or Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end
  if managed_snacks_terminal and managed_snacks_terminal:valid() then
    managed_snacks_terminal:close() -- This should trigger the on_close in snacks_opts
    -- managed_snacks_terminal will be set to nil by the on_close callback defined in build_snacks_opts.
  end
  -- No explicit notification if no terminal to close, to keep it less noisy.
end

--- Toggles the Claude terminal open or closed.
-- Uses `Snacks.terminal.toggle` to manage the terminal state.
-- Updates the `managed_snacks_terminal` state based on the result.
-- @param opts_override table (optional) Overrides for terminal appearance (e.g., split_side, split_width_percentage).
-- These are used by `Snacks.terminal.toggle` if it needs to open a new terminal.
function M.toggle(opts_override)
  if not Snacks or not Snacks.terminal then
    vim.notify("Snacks.nvim or Snacks.terminal not available.", vim.log.levels.ERROR)
    return
  end
  -- The ID for toggle in Snacks is based on cmd, cwd, env.
  -- We'll use our specific claude_command to ensure we toggle the correct terminal.
  local claude_command = get_claude_command()
  local snacks_opts = build_snacks_opts(opts_override)
  -- Snacks.terminal.toggle will handle opening if not found,
  -- or closing if found and it's the same terminal.
  -- It returns the terminal instance if opened/kept open, or nil if closed.
  local term_instance = Snacks.terminal.toggle(claude_command, snacks_opts)
  if term_instance and term_instance:valid() then
    managed_snacks_terminal = term_instance
  else
    -- If term_instance is nil or not valid, it means the terminal was closed or failed to open.
    -- The on_close callback in snacks_opts (if triggered by close) is the primary mechanism
    -- for clearing managed_snacks_terminal.
    -- This explicit nil assignment ensures our reference is cleared if toggle results
    -- in a non-open state or if opening failed.
    managed_snacks_terminal = nil
  end
end

-- M._on_claude_term_exit is no longer needed as Snacks `interactive=true` handles auto-close,
-- and the `on_close` callback in `snacks_opts.win` handles clearing our state.

return M
