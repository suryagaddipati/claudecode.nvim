require("tests.busted_setup")
require("tests.mocks.vim")

describe("claudecode.init", function()
  ---@class AutocmdOptions
  ---@field group string|number|nil
  ---@field pattern string|string[]|nil
  ---@field buffer number|nil
  ---@field desc string|nil
  ---@field callback function|nil
  ---@field once boolean|nil
  ---@field nested boolean|nil

  local saved_vim_api = vim.api
  local saved_vim_deepcopy = vim.deepcopy
  local saved_vim_tbl_deep_extend = vim.tbl_deep_extend
  local saved_vim_notify = vim.notify
  local saved_vim_fn = vim.fn
  local saved_vim_log = vim.log
  local saved_require = _G.require

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
          -- args is unused but keeping the parameter for clarity, as the function signature might be relevant for future tests
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

  local match = {
    is_table = function()
      return { is_table = true }
    end,
  }

  before_each(function()
    vim.api = {
      nvim_create_autocmd = SpyObject.new(function() end),
      nvim_create_augroup = SpyObject.new(function()
        return 1
      end),
      nvim_create_user_command = SpyObject.new(function() end),
    }

    vim.deepcopy = function(t)
      return t
    end

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
        NONE = 0,
        INFO = 2,
        WARN = 3,
        ERROR = 4,
        DEBUG = 5,
        TRACE = 6,
      },
    }

    mock_server.stop = SpyObject.new(mock_server.stop)
    mock_lockfile.remove = SpyObject.new(mock_lockfile.remove)

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

    _G.match = match
  end)

  after_each(function()
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

      assert(#vim.api.nvim_create_augroup.calls > 0, "nvim_create_augroup was not called")
      assert(#vim.api.nvim_create_autocmd.calls > 0, "nvim_create_autocmd was not called")

      assert(vim.api.nvim_create_autocmd.calls[1].vals[1] == "VimLeavePre", "Expected VimLeavePre event")
    end)
  end)

  describe("auto-shutdown", function()
    it("should stop the server and remove lockfile when Neovim exits", function()
      local claudecode = require("claudecode")
      claudecode.setup()
      claudecode.start()

      local opts = vim.api.nvim_create_autocmd.calls[1].vals[2]
      local callback_fn = opts.callback

      mock_server.stop.calls = {}
      mock_lockfile.remove.calls = {}

      if callback_fn then
        callback_fn()
      end

      assert(#mock_server.stop.calls > 0, "Server stop was not called")
      assert(#mock_lockfile.remove.calls > 0, "Lockfile remove was not called")
    end)

    it("should do nothing if the server is not running", function()
      local claudecode = require("claudecode")
      claudecode.setup({ auto_start = false })

      local opts = vim.api.nvim_create_autocmd.calls[1].vals[2]
      local callback_fn = opts.callback

      mock_server.stop.calls = {}
      mock_lockfile.remove.calls = {}

      if callback_fn then
        callback_fn()
      end

      assert(#mock_server.stop.calls == 0, "Server stop was called unexpectedly")
      assert(#mock_lockfile.remove.calls == 0, "Lockfile remove was called unexpectedly")
    end)
  end)
end)
