-- Unit tests for configuration module
-- luacheck: globals expect
require("tests.busted_setup")

describe("Configuration", function()
  local config

  -- Set up before each test
  local function setup()
    -- Reset loaded modules
    package.loaded["claudecode.config"] = nil

    -- Load the module under test
    config = require("claudecode.config")
  end

  -- Clean up after each test
  local function teardown()
    -- Nothing to clean up for now
  end

  -- Run setup before each test
  setup()

  it("should have default configuration", function()
    expect(config.defaults).to_be_table()
    expect(config.defaults).to_have_key("port_range")
    expect(config.defaults).to_have_key("auto_start")
    expect(config.defaults).to_have_key("log_level")
    expect(config.defaults).to_have_key("track_selection")
  end)

  it("should validate valid configuration", function()
    local valid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      terminal_cmd = "toggleterm",
      log_level = "debug",
      track_selection = false,
    }

    local success = config.validate(valid_config)
    expect(success).to_be_true()
  end)

  it("should reject invalid port range", function()
    local invalid_config = {
      port_range = { min = -1, max = 65536 },
      auto_start = true,
      log_level = "debug",
      track_selection = false,
    }

    local success, _ = pcall(function() -- Use _ for unused error variable
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
    -- Error message would contain "Invalid port range"
  end)

  it("should reject invalid log level", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "invalid_level",
      track_selection = false,
    }

    local success, _ = pcall(function() -- Use _ for unused error variable
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
    -- Error message would contain "log_level must be one of"
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      auto_start = true,
      log_level = "debug",
    }

    local merged_config = config.apply(user_config)

    expect(merged_config.auto_start).to_be_true()
    expect(merged_config.log_level).to_be("debug")
    expect(merged_config.port_range.min).to_be(config.defaults.port_range.min)
    expect(merged_config.track_selection).to_be(config.defaults.track_selection)
  end)

  -- Clean up after all tests
  teardown()
end)
