describe("claudecode.init", function()
  local mock_api = {
    nvim_create_autocmd = function() end,
    nvim_create_augroup = function()
      return 1
    end,
  }

  local mock_server = {
    start = function()
      return true, 12345
    end,
    stop = function()
      return true
    end,
  }

  local mock_lockfile = {
    create = function()
      return true, "/mock/path"
    end,
    remove = function()
      return true
    end,
  }

  before_each(function()
    -- Save original modules
    _G._saved_vim = _G.vim
    _G._saved_require = _G.require

    -- Set up mocks
    _G.vim = {
      deepcopy = function(t)
        return vim.deepcopy(t)
      end,
      tbl_deep_extend = function(_, default, override)
        return vim.tbl_deep_extend("force", default, override)
      end,
      notify = function() end,
      api = mock_api,
      fn = {
        getpid = function()
          return 123
        end,
        expand = function()
          return "/mock/path"
        end,
      },
      log = {
        levels = {
          INFO = 2,
          WARN = 3,
          ERROR = 4,
        },
      },
    }

    -- Mock require function
    _G.require = function(mod)
      if mod == "claudecode.server" then
        return mock_server
      elseif mod == "claudecode.lockfile" then
        return mock_lockfile
      elseif mod == "claudecode.selection" then
        return {
          enable = function() end,
          disable = function() end,
        }
      else
        return _G._saved_require(mod)
      end
    end

    -- Spy on functions
    spy.on(mock_api, "nvim_create_autocmd")
    spy.on(mock_api, "nvim_create_augroup")
    spy.on(mock_server, "stop")
    spy.on(mock_lockfile, "remove")
  end)

  after_each(function()
    -- Restore original modules
    _G.vim = _G._saved_vim
    _G.require = _G._saved_require
  end)

  describe("setup", function()
    it("should register VimLeavePre autocmd for auto-shutdown", function()
      local claudecode = require("claudecode")
      claudecode.setup()

      assert.spy(mock_api.nvim_create_augroup).was_called(1)
      assert.spy(mock_api.nvim_create_autocmd).was_called(1)
      assert.spy(mock_api.nvim_create_autocmd).was_called_with("VimLeavePre", match.is_table())
    end)
  end)

  describe("auto-shutdown", function()
    it("should stop the server and remove lockfile when Neovim exits", function()
      local claudecode = require("claudecode")
      claudecode.setup()
      claudecode.start()

      -- Get the callback function from the autocmd call
      local callback_fn = mock_api.nvim_create_autocmd.calls[1].vals[2].callback

      -- Call the callback function to simulate VimLeavePre event
      callback_fn()

      -- Verify that stop was called
      assert.spy(mock_server.stop).was_called(1)
      assert.spy(mock_lockfile.remove).was_called(1)
    end)

    it("should do nothing if the server is not running", function()
      local claudecode = require("claudecode")
      claudecode.setup()

      -- Get the callback function from the autocmd call
      local callback_fn = mock_api.nvim_create_autocmd.calls[1].vals[2].callback

      -- Call the callback function to simulate VimLeavePre event
      callback_fn()

      -- Verify that stop was not called
      assert.spy(mock_server.stop).was_not_called()
      assert.spy(mock_lockfile.remove).was_not_called()
    end)
  end)
end)
