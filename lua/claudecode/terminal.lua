--- Module to manage a dedicated vertical split terminal for Claude Code.
-- Supports Snacks.nvim or a native Neovim terminal fallback.
-- @module claudecode.terminal
-- @plugin snacks.nvim (optional)

local M = {}

local snacks_available, Snacks = pcall(require, "snacks")
if not snacks_available then
  Snacks = nil
  vim.notify(
    "Snacks.nvim not found. ClaudeCode will use built-in Neovim terminal if configured or as fallback.",
    vim.log.levels.INFO
  )
end

local claudecode_config_module = require("claudecode.config")

local term_module_config = {
  split_side = "right", -- 'left' or 'right'
  split_width_percentage = 0.30, -- e.g., 0.30 for 30%
  provider = "snacks", -- "snacks" or "native"
  show_native_term_exit_tip = true, -- Show tip for Ctrl-\\ Ctrl-N
}

--- State to keep track of the managed Claude terminal instance (from Snacks).
-- @type table|nil #snacks_terminal_instance The Snacks terminal instance, or nil if not active.
local managed_snacks_terminal = nil

local managed_fallback_terminal_bufnr = nil
local managed_fallback_terminal_winid = nil
local managed_fallback_terminal_jobid = nil
local native_term_tip_shown = false

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

--- Configures the terminal module.
-- Merges user-provided terminal configuration with defaults.
-- @param user_term_config table (optional) Configuration options for the terminal.
-- @field user_term_config.split_side string 'left' or 'right' (default: 'right').
-- @field user_term_config.split_width_percentage number Percentage of screen width (0.0 to 1.0, default: 0.30).
-- @field user_term_config.provider string 'snacks' or 'native' (default: 'snacks').
-- @field user_term_config.show_native_term_exit_tip boolean Show tip for exiting native terminal (default: true).
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
      elseif k == "provider" and (v == "snacks" or v == "native") then
        term_module_config[k] = v
      elseif k == "show_native_term_exit_tip" and type(v) == "boolean" then
        term_module_config[k] = v
      else
        vim.notify("claudecode.terminal.setup: Invalid value for " .. k .. ": " .. tostring(v), vim.log.levels.WARN)
      end
    else
      vim.notify("claudecode.terminal.setup: Unknown configuration key: " .. k, vim.log.levels.WARN)
    end
  end
end

--- Determines the effective terminal provider based on configuration and availability.
-- @local
-- @return string "snacks" or "native"
local function get_effective_terminal_provider()
  if term_module_config.provider == "snacks" then
    if snacks_available then
      return "snacks"
    else
      vim.notify(
        "ClaudeCode: 'snacks' provider configured, but Snacks.nvim not available. Falling back to 'native'.",
        vim.log.levels.WARN
      )
      return "native"
    end
  elseif term_module_config.provider == "native" then
    return "native"
  else
    vim.notify(
      "ClaudeCode: Invalid provider configured: "
        .. tostring(term_module_config.provider)
        .. ". Defaulting to 'native'.",
      vim.log.levels.WARN
    )
    return "native" -- Default to native if misconfigured
  end
end

--- Cleans up state variables for the fallback terminal.
-- @local
local function cleanup_fallback_terminal_state()
  managed_fallback_terminal_bufnr = nil
  managed_fallback_terminal_winid = nil
  managed_fallback_terminal_jobid = nil
end

--- Checks if the managed fallback terminal is currently valid (window and buffer exist).
-- Cleans up state if invalid.
-- @local
-- @return boolean True if valid, false otherwise.
local function is_fallback_terminal_valid()
  if managed_fallback_terminal_winid and vim.api.nvim_win_is_valid(managed_fallback_terminal_winid) then
    if managed_fallback_terminal_bufnr and vim.api.nvim_buf_is_valid(managed_fallback_terminal_bufnr) then
      return true
    end
  end
  -- If any check fails or state vars are nil, cleanup and return false
  cleanup_fallback_terminal_state()
  return false
end

--- Opens a new terminal using native Neovim functions.
-- @local
-- @param command string The command to run.
-- @param effective_term_config table Configuration for split_side and split_width_percentage.
-- @return boolean True if successful, false otherwise.
local function open_fallback_terminal(command, effective_term_config)
  if is_fallback_terminal_valid() then -- Should not happen if called correctly, but as a safeguard
    vim.api.nvim_set_current_win(managed_fallback_terminal_winid)
    vim.cmd("startinsert")
    return true
  end

  local original_win = vim.api.nvim_get_current_win()

  local width = math.floor(vim.o.columns * effective_term_config.split_width_percentage)
  local full_height = vim.o.lines
  local placement_modifier

  if effective_term_config.split_side == "left" then
    placement_modifier = "topleft "
  else
    placement_modifier = "botright "
  end

  vim.cmd(placement_modifier .. width .. "vsplit")

  local new_winid = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_height(new_winid, full_height)

  vim.api.nvim_win_call(new_winid, function()
    vim.cmd("enew")
  end)
  -- Note: vim.api.nvim_win_set_width is not needed here again as [N]vsplit handles it.

  managed_fallback_terminal_jobid = vim.fn.termopen(command, {
    on_exit = function(job_id, code, event)
      vim.schedule(function()
        if job_id == managed_fallback_terminal_jobid then
          -- Ensure we are operating on the correct window and buffer before closing
          local current_winid_for_job = managed_fallback_terminal_winid
          local current_bufnr_for_job = managed_fallback_terminal_bufnr

          cleanup_fallback_terminal_state() -- Clear our managed state first

          if current_winid_for_job and vim.api.nvim_win_is_valid(current_winid_for_job) then
            if current_bufnr_for_job and vim.api.nvim_buf_is_valid(current_bufnr_for_job) then
              -- Optional: Check if the window still holds the same terminal buffer
              if vim.api.nvim_win_get_buf(current_winid_for_job) == current_bufnr_for_job then
                vim.api.nvim_win_close(current_winid_for_job, true) -- Force close
              end
            else
              -- Buffer is invalid, but window might still be there (e.g. if user changed buffer in term window)
              -- Still try to close the window we tracked.
              vim.api.nvim_win_close(current_winid_for_job, true)
            end
          end
        end
      end)
    end,
  })

  if not managed_fallback_terminal_jobid or managed_fallback_terminal_jobid == 0 then
    vim.notify("Failed to open native terminal.", vim.log.levels.ERROR)
    vim.api.nvim_win_close(new_winid, true) -- Close the split we opened
    vim.api.nvim_set_current_win(original_win) -- Restore original window
    cleanup_fallback_terminal_state()
    return false
  end

  managed_fallback_terminal_winid = new_winid
  managed_fallback_terminal_bufnr = vim.api.nvim_get_current_buf()
  vim.bo[managed_fallback_terminal_bufnr].bufhidden = "wipe" -- Wipe buffer when hidden (e.g., window closed)
  -- buftype=terminal is set by termopen

  vim.api.nvim_set_current_win(managed_fallback_terminal_winid)
  vim.cmd("startinsert")

  if term_module_config.show_native_term_exit_tip and not native_term_tip_shown then
    vim.notify("Native terminal opened. Press Ctrl-\\ Ctrl-N to return to Normal mode.", vim.log.levels.INFO)
    native_term_tip_shown = true
  end
  return true
end

--- Closes the managed fallback terminal if it's open and valid.
-- @local
local function close_fallback_terminal()
  if is_fallback_terminal_valid() then
    -- Closing the window should trigger on_exit of the job if the process is still running,
    -- which then calls cleanup_fallback_terminal_state.
    -- If the job already exited, on_exit would have cleaned up.
    -- This direct close is for user-initiated close.
    vim.api.nvim_win_close(managed_fallback_terminal_winid, true)
    cleanup_fallback_terminal_state() -- Ensure cleanup if on_exit doesn't fire (e.g. job already dead)
  end
end

--- Focuses the managed fallback terminal if it's open and valid.
-- @local
local function focus_fallback_terminal()
  if is_fallback_terminal_valid() then
    vim.api.nvim_set_current_win(managed_fallback_terminal_winid)
    vim.cmd("startinsert")
  end
end

--- Builds the effective terminal configuration by merging module defaults with runtime overrides.
-- Used by the native fallback.
-- @local
-- @param opts_override table (optional) Overrides for terminal appearance (split_side, split_width_percentage).
-- @return table The effective terminal configuration.
local function build_effective_term_config(opts_override)
  local effective_config = vim.deepcopy(term_module_config)
  if type(opts_override) == "table" then
    local validators = {
      split_side = function(val)
        return val == "left" or val == "right"
      end,
      split_width_percentage = function(val)
        return type(val) == "number" and val > 0 and val < 1
      end,
    }
    for key, val in pairs(opts_override) do
      if effective_config[key] ~= nil and validators[key] and validators[key](val) then
        effective_config[key] = val
      end
    end
  end
  return {
    split_side = effective_config.split_side,
    split_width_percentage = effective_config.split_width_percentage,
  }
end

--- Builds the options table for Snacks.terminal.
-- This function merges the module's current terminal configuration
-- with any runtime overrides provided specifically for an open/toggle action.
-- @local
-- @param effective_term_config_for_snacks table Pre-calculated effective config for split_side, width.
-- @return table The options table for Snacks.
local function build_snacks_opts(effective_term_config_for_snacks)
  return {
    interactive = true, -- for auto_close and start_insert
    enter = true, -- focus the terminal when opened
    win = {
      position = effective_term_config_for_snacks.split_side,
      width = effective_term_config_for_snacks.split_width_percentage, -- snacks.win uses <1 for relative width
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
function M.open(opts_override)
  local provider = get_effective_terminal_provider()
  local claude_command = get_claude_command()
  local effective_config = build_effective_term_config(opts_override)

  if not claude_command or claude_command == "" then -- Should not happen due to default in get_claude_command
    vim.notify("Claude terminal command cannot be determined.", vim.log.levels.ERROR)
    return
  end

  if provider == "snacks" then
    if not Snacks or not Snacks.terminal then -- Should be caught by snacks_available, but defensive
      vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
      return
    end
    if managed_snacks_terminal and managed_snacks_terminal:valid() then
      managed_snacks_terminal:focus()
      local term_buf_id = managed_snacks_terminal.buf
      if term_buf_id and vim.api.nvim_buf_get_option(term_buf_id, "buftype") == "terminal" then
        vim.api.nvim_win_call(managed_snacks_terminal.winid, function()
          vim.cmd("startinsert")
        end)
      end
      return
    end
    local snacks_opts = build_snacks_opts(effective_config)
    local term_instance = Snacks.terminal.open(claude_command, snacks_opts)
    if term_instance and term_instance:valid() then
      managed_snacks_terminal = term_instance
    else
      vim.notify("Failed to open Claude terminal using Snacks.", vim.log.levels.ERROR)
      managed_snacks_terminal = nil
    end
  elseif provider == "native" then
    if is_fallback_terminal_valid() then
      focus_fallback_terminal()
    else
      if not open_fallback_terminal(claude_command, effective_config) then
        vim.notify("Failed to open Claude terminal using native fallback.", vim.log.levels.ERROR)
      end
    end
  end
end

--- Closes the managed Claude terminal if it's open and valid.
function M.close()
  local provider = get_effective_terminal_provider()
  if provider == "snacks" then
    if not Snacks or not Snacks.terminal then
      return
    end -- Defensive
    if managed_snacks_terminal and managed_snacks_terminal:valid() then
      managed_snacks_terminal:close()
      -- managed_snacks_terminal will be set to nil by the on_close callback
    end
  elseif provider == "native" then
    close_fallback_terminal()
  end
end

--- Toggles the Claude terminal open or closed.
function M.toggle(opts_override)
  local provider = get_effective_terminal_provider()
  local claude_command = get_claude_command()
  local effective_config = build_effective_term_config(opts_override)

  if not claude_command or claude_command == "" then
    vim.notify("Claude terminal command cannot be determined.", vim.log.levels.ERROR)
    return
  end

  if provider == "snacks" then
    if not Snacks or not Snacks.terminal then
      vim.notify("Snacks.nvim terminal provider selected but Snacks.terminal not available.", vim.log.levels.ERROR)
      return
    end
    local snacks_opts = build_snacks_opts(effective_config)
    local term_instance = Snacks.terminal.toggle(claude_command, snacks_opts)
    if term_instance and term_instance:valid() then
      managed_snacks_terminal = term_instance
    else
      managed_snacks_terminal = nil -- Snacks.toggle returns nil if closed or failed
    end
  elseif provider == "native" then
    if is_fallback_terminal_valid() then
      close_fallback_terminal()
    else
      if not open_fallback_terminal(claude_command, effective_config) then
        vim.notify("Failed to open Claude terminal using native fallback (toggle).", vim.log.levels.ERROR)
      end
    end
  end
end

return M
