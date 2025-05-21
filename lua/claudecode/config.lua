--- Manages configuration for the Claude Code Neovim integration.
-- Provides default settings, validation, and application of user-defined configurations.
local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,
  log_level = "info",
  track_selection = true,
}

--- Validates the provided configuration table.
-- Ensures that all configuration options are of the correct type and within valid ranges.
-- @param config table The configuration table to validate.
-- @return boolean true if the configuration is valid.
-- @error string if any configuration option is invalid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")

  return true
end

--- Applies user configuration on top of default settings and validates the result.
-- Merges the user-provided configuration with the default configuration,
-- then validates the merged configuration.
-- @param user_config table|nil The user-provided configuration table.
-- @return table The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  M.validate(config)

  return config
end

return M
