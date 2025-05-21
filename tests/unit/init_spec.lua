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

  local mock_api = {
    ---@type SpyableFunction
    nvim_create_autocmd = function() end,
    ---@type SpyableFunction
    nvim_create_augroup = function()
      return 1
    end,
    nvim_create_user_command = function() end, -- Add this missing function
  }

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

  before_each(function()
    -- Set up mocks by modifying properties of vim
    vim.api = mock_api
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

    -- Spy on functions
    spy.on(mock_api, "nvim_create_autocmd")
    spy.on(mock_api, "nvim_create_augroup")
    spy.on(mock_server, "stop")
    spy.on(mock_lockfile, "remove")
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

      ---@type SpyAsserts
      local spy_augroup_asserts = mock_api.nvim_create_augroup:spy()
      spy_augroup_asserts.was_called(1)
      ---@type SpyAsserts
      local spy_autocmd_asserts = mock_api.nvim_create_autocmd:spy()
      spy_autocmd_asserts.was_called(1)
      spy_autocmd_asserts.was_called_with("VimLeavePre", match.is_table())
    end)
  end)

  describe("auto-shutdown", function()
    it("should stop the server and remove lockfile when Neovim exits", function()
      local claudecode = require("claudecode")
      claudecode.setup()
      claudecode.start()

      -- Get the callback function from the autocmd call
      local opts = mock_api.nvim_create_autocmd.calls[1].vals[2] ---@type AutocmdOptions
      local callback_fn = opts.callback

      -- Call the callback function to simulate VimLeavePre event
      if callback_fn then
        callback_fn()
      end

      -- Verify that stop was called
      ---@type SpyAsserts
      local spy_server_stop_asserts = mock_server.stop:spy()
      spy_server_stop_asserts.was_called(1)
      ---@type SpyAsserts
      local spy_lockfile_remove_asserts = mock_lockfile.remove:spy()
      spy_lockfile_remove_asserts.was_called(1)
    end)

    it("should do nothing if the server is not running", function()
      local claudecode = require("claudecode")
      claudecode.setup({ auto_start = false })

      -- Get the callback function from the autocmd call
      local opts = mock_api.nvim_create_autocmd.calls[1].vals[2] ---@type AutocmdOptions
      local callback_fn = opts.callback

      -- Call the callback function to simulate VimLeavePre event
      if callback_fn then
        callback_fn()
      end

      -- Verify that stop was not called
      ---@type SpyAsserts
      local spy_server_stop_not_asserts = mock_server.stop:spy()
      spy_server_stop_not_asserts.was_not_called()
      ---@type SpyAsserts
      local spy_lockfile_remove_not_asserts = mock_lockfile.remove:spy()
      spy_lockfile_remove_not_asserts.was_not_called()
    end)
  end)
end)
