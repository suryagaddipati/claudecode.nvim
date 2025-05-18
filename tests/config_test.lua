-- Simple config module tests that don't rely on the vim API

-- Create minimal vim mock
_G.vim = {
  deepcopy = function(t)
    local copy = {}
    for k, v in pairs(t) do
      if type(v) == "table" then
        copy[k] = _G.vim.deepcopy(v)
      else
        copy[k] = v
      end
    end
    return copy
  end,

  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local tables = { ... }

    for _, tbl in ipairs(tables) do
      for k, v in pairs(tbl) do
        if type(v) == "table" and type(result[k]) == "table" then
          result[k] = _G.vim.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = v
        end
      end
    end

    return result
  end,
}

describe("Config module", function()
  local config

  -- Set up before each test
  setup(function()
    -- Reset the module
    package.loaded["claudecode.config"] = nil

    -- Load module
    config = require("claudecode.config")
  end)

  it("should have default values", function()
    assert.is_table(config.defaults)
    assert.is_table(config.defaults.port_range)
    assert.is_number(config.defaults.port_range.min)
    assert.is_number(config.defaults.port_range.max)
    assert.is_boolean(config.defaults.auto_start)
    assert.is_string(config.defaults.log_level)
    assert.is_boolean(config.defaults.track_selection)
  end)

  it("should validate valid configuration", function()
    local valid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      terminal_cmd = "toggleterm",
      log_level = "debug",
      track_selection = false,
    }

    local success, _ = pcall(function()
      return config.validate(valid_config)
    end)

    assert.is_true(success)
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      auto_start = true,
      log_level = "debug",
    }

    local merged_config = config.apply(user_config)

    assert.is_true(merged_config.auto_start)
    assert.equals("debug", merged_config.log_level)
    assert.equals(config.defaults.port_range.min, merged_config.port_range.min)
    assert.equals(config.defaults.track_selection, merged_config.track_selection)
  end)
end)
