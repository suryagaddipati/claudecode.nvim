-- Configuration management for Claude Code Neovim integration
local M = {}

-- Default configuration
M.defaults = {
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

-- Validate configuration
function M.validate(config)
  -- Validate port range
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  -- Validate auto_start
  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  -- Validate terminal_cmd
  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  -- Validate log_level
  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  -- Validate track_selection
  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")

  return true
end

-- Apply configuration with validation
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Validate the merged configuration
  M.validate(config)

  return config
end

return M
