-- Simple config module tests that don't rely on the vim API

-- Create minimal vim mock
_G.vim = { ---@type vim_global_api
  deepcopy = function(t)
    -- Basic deepcopy for testing
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
        -- vim.bo[bufnr] accessed, return a new proxy table for this buffer
        if not t[k] then
          t[k] = {} ---@type vim_buffer_options_table
        end
        return t[k]
      end
      -- vim.bo.option_name (global buffer option)
      -- Return nil or a default mock value if needed
      return nil
    end,
    __newindex = function(t, k, v)
      if type(k) == "number" then
        -- vim.bo[bufnr] = val (should not happen for options table itself)
        -- or vim.bo[bufnr].opt = val
        -- For simplicity, allow setting on the dynamic buffer table
        if not t[k] then
          t[k] = {}
        end
        rawset(t[k], v) -- Assuming v is the option name if k is bufnr, this is simplified
      else
        -- vim.bo.option_name = val
        rawset(t, k, v)
      end
    end,
  }), ---@type vim_bo_proxy
  diagnostic = { ---@type vim_diagnostic_module
    get = function()
      return {}
    end,
    -- Add other vim.diagnostic functions as needed for tests
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

  -- Set up before each test
  setup(function()
    -- Reset the module
    package.loaded["claudecode.config"] = nil

    -- Load module
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
