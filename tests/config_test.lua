-- Simple config module tests that don't rely on the vim API

_G.vim = { ---@type vim_global_api
  deepcopy = function(t)
    -- Basic deepcopy implementation for testing purposes
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
  notify = function(_, _, _) end,
  log = {
    levels = {
      NONE = 0,
      ERROR = 1,
      WARN = 2,
      INFO = 3,
      DEBUG = 4,
      TRACE = 5,
    },
  },
  o = {}, ---@type vim_options_table
  bo = setmetatable({}, { -- Mock for vim.bo and vim.bo[bufnr]
    __index = function(t, k)
      if type(k) == "number" then
        if not t[k] then
          t[k] = {} ---@type vim_buffer_options_table
        end
        return t[k]
      end
      return nil
    end,
    __newindex = function(t, k, v)
      if type(k) == "number" then
        -- For mock simplicity, allows direct setting for vim.bo[bufnr].opt = val or similar assignments.
        if not t[k] then
          t[k] = {}
        end
        rawset(t[k], v) -- Assuming v is the option name if k is bufnr, this is simplified
      else
        rawset(t, k, v)
      end
    end,
  }), ---@type vim_bo_proxy
  diagnostic = { ---@type vim_diagnostic_module
    get = function()
      return {}
    end,
    -- Add other vim.diagnostic functions as needed for these tests
  },
  empty_dict = function()
    return {}
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

  setup(function()
    -- Reset the module to ensure a clean state for each test
    package.loaded["claudecode.config"] = nil

    config = require("claudecode.config")
  end)

  it("should have default values", function()
    assert(type(config.defaults) == "table")
    assert(type(config.defaults.port_range) == "table")
    assert(type(config.defaults.port_range.min) == "number")
    assert(type(config.defaults.port_range.max) == "number")
    assert(type(config.defaults.auto_start) == "boolean")
    assert(type(config.defaults.log_level) == "string")
    assert(type(config.defaults.track_selection) == "boolean")
  end)

  it("should validate valid configuration", function()
    local valid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      terminal_cmd = "toggleterm",
      log_level = "debug",
      track_selection = false,
      visual_demotion_delay_ms = 50,
    }

    local success, _ = pcall(function()
      return config.validate(valid_config)
    end)

    assert(success == true)
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      auto_start = true,
      log_level = "debug",
    }

    local merged_config = config.apply(user_config)

    assert(merged_config.auto_start == true)
    assert("debug" == merged_config.log_level)
    assert(config.defaults.port_range.min == merged_config.port_range.min)
    assert(config.defaults.track_selection == merged_config.track_selection)
  end)
end)
