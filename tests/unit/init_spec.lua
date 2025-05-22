require("tests.busted_setup")
require("tests.mocks.vim") -- Add mock vim for testing

describe("claudecode.init", function()
  ---@class AutocmdOptions
  ---@field group string|number|nil
  ---@field pattern string|string[]|nil
  ---@field buffer number|nil
  ---@field desc string|nil
  ---@field callback function|nil
  ---@field once boolean|nil
  ---@field nested boolean|nil

  -- Save original functions
  local saved_vim_api = vim.api
  local saved_vim_deepcopy = vim.deepcopy
  local saved_vim_tbl_deep_extend = vim.tbl_deep_extend
  local saved_vim_notify = vim.notify
  local saved_vim_fn = vim.fn
  local saved_vim_log = vim.log
  local saved_require = _G.require

  -- Variables for mocks are now unused but keeping for reference (commented out)
  -- These functions are now created directly in before_each

  local mock_server = {
    start = function()
      return true, 12345
    end,
    ---@type SpyableFunction
    stop = function()
      return true
    end,
  }

  local mock_lockfile = {
    create = function()
      return true, "/mock/path"
    end,
    ---@type SpyableFunction
    remove = function()
      return true
    end,
  }

  local mock_selection = {
    enable = function() end,
    disable = function() end,
  }

  -- Simplified SpyObject implementation
  local SpyObject = {}
  function SpyObject.new(fn)
    local spy_obj = {
      _original = fn,
      calls = {},
    }

    function spy_obj.spy()
      return {
        was_called = function(n)
          assert(#spy_obj.calls == n, "Expected " .. n .. " calls, got " .. #spy_obj.calls)
          return true
        end,
        was_not_called = function()
          assert(#spy_obj.calls == 0, "Expected 0 calls, got " .. #spy_obj.calls)
          return true
        end,
        was_called_with = function(...)
          -- args is unused but keeping the parameter for clarity
          assert(#spy_obj.calls > 0, "Function was never called")
          return true
        end,
      }
    end

    return setmetatable(spy_obj, {
      __call = function(self, ...)
        table.insert(self.calls, { vals = { ... } })
        if self._original then
          return self._original(...)
        end
      end,
    })
  end

  -- Create match table for assertions
  local match = {
    is_table = function()
      return { is_table = true }
    end,
  }

  before_each(function()
    -- Set up mocks by modifying properties of vim
    vim.api = {
      nvim_create_autocmd = SpyObject.new(function() end),
      nvim_create_augroup = SpyObject.new(function()
        return 1
      end),
      nvim_create_user_command = SpyObject.new(function() end),
    }

    vim.deepcopy = function(t)
      return t
    end -- Simple mock

    vim.tbl_deep_extend = function(_, default, override)
      local result = {}
      for k, v in pairs(default) do
        result[k] = v
      end
      for k, v in pairs(override) do
        result[k] = v
      end
      return result
    end

    vim.notify = function() end

    vim.fn = {
      getpid = function()
        return 123
      end,
      expand = function()
        return "/mock/path"
      end,
    }

    vim.log = {
      levels = {
        NONE = 0, -- Added
        INFO = 2,
        WARN = 3,
        ERROR = 4,
        DEBUG = 5, -- Added
        TRACE = 6, -- Added
      },
    }

    -- Create spy objects for mock functions
    mock_server.stop = SpyObject.new(mock_server.stop)
    mock_lockfile.remove = SpyObject.new(mock_lockfile.remove)

    -- Mock require function to return our mocks
    _G.require = function(mod)
      if mod == "claudecode.server" then
        return mock_server
      elseif mod == "claudecode.lockfile" then
        return mock_lockfile
      elseif mod == "claudecode.selection" then
        return mock_selection
      else
        return saved_require(mod)
      end
    end

    -- Set match in global scope for tests
    _G.match = match
  end)

  after_each(function()
    -- Restore original functions
    vim.api = saved_vim_api
    vim.deepcopy = saved_vim_deepcopy
    vim.tbl_deep_extend = saved_vim_tbl_deep_extend
    vim.notify = saved_vim_notify
    vim.fn = saved_vim_fn
    vim.log = saved_vim_log
    _G.require = saved_require
  end)

  describe("setup", function()
    it("should register VimLeavePre autocmd for auto-shutdown", function()
      local claudecode = require("claudecode")
      claudecode.setup()

      -- Simply check if the functions were called
      assert(#vim.api.nvim_create_augroup.calls > 0, "nvim_create_augroup was not called")
      assert(#vim.api.nvim_create_autocmd.calls > 0, "nvim_create_autocmd was not called")

      -- Check if the first argument to nvim_create_autocmd was "VimLeavePre"
      assert(vim.api.nvim_create_autocmd.calls[1].vals[1] == "VimLeavePre", "Expected VimLeavePre event")
    end)

    it("should correctly set vim.g.claudecode_user_config with terminal_cmd from opts", function()
      local claudecode = require("claudecode")
      local test_cmd = "my-custom-command --flag"
      claudecode.setup({ terminal_cmd = test_cmd })

      assert(vim.g.claudecode_user_config ~= nil, "vim.g.claudecode_user_config was not set")
      assert(
        vim.g.claudecode_user_config.terminal_cmd == test_cmd,
        "vim.g.claudecode_user_config.terminal_cmd was not set correctly. Expected: "
          .. test_cmd
          .. ", Got: "
          .. tostring(vim.g.claudecode_user_config.terminal_cmd)
      )
    end)
  end)

  describe("auto-shutdown", function()
    it("should stop the server and remove lockfile when Neovim exits", function()
      local claudecode = require("claudecode")
      claudecode.setup()
      claudecode.start()

      -- Get the callback function from the autocmd call
      local opts = vim.api.nvim_create_autocmd.calls[1].vals[2]
      local callback_fn = opts.callback

      -- Reset the spy calls
      mock_server.stop.calls = {}
      mock_lockfile.remove.calls = {}

      -- Call the callback function to simulate VimLeavePre event
      if callback_fn then
        callback_fn()
      end

      -- Verify that stop was called
      assert(#mock_server.stop.calls > 0, "Server stop was not called")
      assert(#mock_lockfile.remove.calls > 0, "Lockfile remove was not called")
    end)

    it("should do nothing if the server is not running", function()
      local claudecode = require("claudecode")
      claudecode.setup({ auto_start = false })

      -- Get the callback function from the autocmd call
      local opts = vim.api.nvim_create_autocmd.calls[1].vals[2]
      local callback_fn = opts.callback

      -- Reset the spy calls
      mock_server.stop.calls = {}
      mock_lockfile.remove.calls = {}

      -- Call the callback function to simulate VimLeavePre event
      if callback_fn then
        callback_fn()
      end

      -- Verify that stop was not called
      assert(#mock_server.stop.calls == 0, "Server stop was called unexpectedly")
      assert(#mock_lockfile.remove.calls == 0, "Lockfile remove was called unexpectedly")
    end)
  end)
end)
