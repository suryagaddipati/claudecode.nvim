describe("claudecode.terminal (wrapper for ToggleTerm.nvim)", function()
  local terminal_wrapper
  local spy
  local mock_toggleterm_module
  local mock_toggleterm_terminal
  local mock_claudecode_config_module
  local mock_toggleterm_provider
  local mock_native_provider
  local last_created_mock_term_instance
  local create_mock_terminal_instance

  create_mock_terminal_instance = function(opts)
    --- Internal deepcopy for the mock's own use.
    --- Avoids recursion with spied vim.deepcopy.
    local function internal_deepcopy(tbl)
      if type(tbl) ~= "table" then
        return tbl
      end
      local status, plenary_tablex = pcall(require, "plenary.tablex")
      if status and plenary_tablex and plenary_tablex.deepcopy then
        return plenary_tablex.deepcopy(tbl)
      end
      local lookup_table = {}
      local function _copy(object)
        if type(object) ~= "table" then
          return object
        elseif lookup_table[object] then
          return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
          new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
      end
      return _copy(tbl)
    end

    local instance = {
      window = 1000 + math.random(100),
      bufnr = 2000 + math.random(100),
      _is_valid = true,
      _opts_received = internal_deepcopy(opts),
      _on_exit_callback = opts and opts.on_exit,

      open = spy.new(function(self)
        return self
      end),

      close = spy.new(function(self)
        self.window = nil
        return self
      end),

      toggle = spy.new(function(self)
        if self.window then
          self.window = nil
        else
          self.window = 1000 + math.random(100)
        end
        return self
      end),

      focus = spy.new(function(self)
        return self
      end),
    }

    last_created_mock_term_instance = instance
    return instance
  end

  before_each(function()
    spy = require("luassert.spy")

    -- Mock vim APIs
    _G.vim = require("tests.mocks.vim")

    -- Mock toggleterm provider
    mock_toggleterm_provider = {
      is_available = spy.new(function()
        return true
      end),
      setup = spy.new(function() end),
      open = spy.new(function(cmd_string, env_table, config, focus) end),
      close = spy.new(function() end),
      toggle = spy.new(function(cmd_string, env_table, config) end),
      simple_toggle = spy.new(function(cmd_string, env_table, config) end),
      focus_toggle = spy.new(function(cmd_string, env_table, config) end),
      get_active_bufnr = spy.new(function()
        return nil
      end),
      _get_terminal_for_test = spy.new(function()
        return last_created_mock_term_instance
      end),
    }

    -- Mock native provider
    mock_native_provider = {
      is_available = spy.new(function()
        return true
      end),
      setup = spy.new(function() end),
      open = spy.new(function(cmd_string, env_table, config, focus) end),
      close = spy.new(function() end),
      toggle = spy.new(function(cmd_string, env_table, config) end),
      simple_toggle = spy.new(function(cmd_string, env_table, config) end),
      focus_toggle = spy.new(function(cmd_string, env_table, config) end),
      get_active_bufnr = spy.new(function()
        return nil
      end),
    }

    -- Setup package loading mocks
    package.loaded["claudecode.terminal.toggleterm"] = mock_toggleterm_provider
    package.loaded["claudecode.terminal.native"] = mock_native_provider

    -- Mock claudecode config
    mock_claudecode_config_module = {
      state = {
        port = 12345,
      },
    }
    package.loaded["claudecode.server.init"] = mock_claudecode_config_module

    -- Clear module cache and reload
    package.loaded["claudecode.terminal"] = nil
    terminal_wrapper = require("claudecode.terminal")
  end)

  after_each(function()
    -- Clean up package cache
    package.loaded["claudecode.terminal"] = nil
    package.loaded["claudecode.terminal.toggleterm"] = nil
    package.loaded["claudecode.terminal.native"] = nil
    package.loaded["claudecode.server.init"] = nil
  end)

  describe("setup", function()
    it("should accept valid configuration", function()
      terminal_wrapper.setup({
        split_side = "left",
        split_width_percentage = 0.25,
        provider = "toggleterm",
      })
    end)

    it("should use auto provider by default", function()
      terminal_wrapper.setup({})
      -- Should work without errors
    end)

    it("should reject invalid provider", function()
      terminal_wrapper.setup({
        provider = "invalid",
      })
      -- Should fall back to native provider
    end)
  end)

  describe("provider selection", function()
    it("should use toggleterm when available in auto mode", function()
      terminal_wrapper.setup({ provider = "auto" })
      terminal_wrapper.open()

      assert.spy(mock_toggleterm_provider.open).was_called(1)
      assert.spy(mock_native_provider.open).was_not_called()
    end)

    it("should fall back to native when toggleterm unavailable", function()
      mock_toggleterm_provider.is_available = spy.new(function()
        return false
      end)

      terminal_wrapper.setup({ provider = "auto" })
      terminal_wrapper.open()

      assert.spy(mock_native_provider.open).was_called(1)
    end)

    it("should use toggleterm when explicitly configured", function()
      terminal_wrapper.setup({ provider = "toggleterm" })
      terminal_wrapper.open()

      assert.spy(mock_toggleterm_provider.open).was_called(1)
    end)

    it("should use native when explicitly configured", function()
      terminal_wrapper.setup({ provider = "native" })
      terminal_wrapper.open()

      assert.spy(mock_native_provider.open).was_called(1)
      assert.spy(mock_toggleterm_provider.open).was_not_called()
    end)
  end)

  describe("terminal operations", function()
    before_each(function()
      terminal_wrapper.setup({ provider = "toggleterm" })
    end)

    it("should pass command and environment to provider", function()
      terminal_wrapper.open("--test-arg")

      assert.spy(mock_toggleterm_provider.open).was_called(1)
      local cmd_arg = mock_toggleterm_provider.open:get_call(1).refs[1]
      local env_arg = mock_toggleterm_provider.open:get_call(1).refs[2]

      assert.is_string(cmd_arg)
      assert.is_table(env_arg)
      assert.are.equal("true", env_arg.ENABLE_IDE_INTEGRATION)
      assert.are.equal("12345", env_arg.CLAUDE_CODE_SSE_PORT)
    end)

    it("should handle toggle operations", function()
      terminal_wrapper.toggle()
      assert.spy(mock_toggleterm_provider.simple_toggle).was_called(1)
    end)

    it("should handle focus toggle operations", function()
      terminal_wrapper.focus_toggle()
      assert.spy(mock_toggleterm_provider.focus_toggle).was_called(1)
    end)

    it("should handle close operations", function()
      terminal_wrapper.close()
      assert.spy(mock_toggleterm_provider.close).was_called(1)
    end)

    it("should get active buffer number", function()
      terminal_wrapper.get_active_bufnr()
      assert.spy(mock_toggleterm_provider.get_active_bufnr).was_called(1)
    end)
  end)

  describe("configuration options", function()
    it("should pass configuration to provider", function()
      terminal_wrapper.setup({
        split_side = "left",
        split_width_percentage = 0.4,
        provider = "toggleterm",
        auto_close = false,
      })

      terminal_wrapper.open()
      
      local config_arg = mock_toggleterm_provider.open:get_call(1).refs[3]
      assert.are.equal("left", config_arg.split_side)
      assert.are.equal(0.4, config_arg.split_width_percentage)
      assert.are.equal(false, config_arg.auto_close)
    end)

    it("should use default configuration when not specified", function()
      terminal_wrapper.setup({})
      terminal_wrapper.open()
      
      local config_arg = mock_toggleterm_provider.open:get_call(1).refs[3]
      assert.are.equal("right", config_arg.split_side)
      assert.are.equal(0.30, config_arg.split_width_percentage)
      assert.are.equal(true, config_arg.auto_close)
    end)
  end)

  describe("command building", function()
    before_each(function()
      terminal_wrapper.setup({ provider = "toggleterm" })
    end)

    it("should build command with arguments", function()
      terminal_wrapper.open("--resume")
      
      local cmd_arg = mock_toggleterm_provider.open:get_call(1).refs[1]
      assert.is_true(string.find(cmd_arg, "--resume") ~= nil)
    end)

    it("should build command without arguments", function()
      terminal_wrapper.open()
      
      local cmd_arg = mock_toggleterm_provider.open:get_call(1).refs[1]
      assert.is_string(cmd_arg)
    end)

    it("should include environment variables", function()
      terminal_wrapper.open()
      
      local env_arg = mock_toggleterm_provider.open:get_call(1).refs[2]
      assert.are.equal("true", env_arg.ENABLE_IDE_INTEGRATION)
      assert.are.equal("true", env_arg.FORCE_CODE_TERMINAL)
      assert.are.equal("12345", env_arg.CLAUDE_CODE_SSE_PORT)
    end)
  end)

  describe("error handling", function()
    it("should handle missing server port gracefully", function()
      mock_claudecode_config_module.state.port = nil
      
      terminal_wrapper.setup({ provider = "toggleterm" })
      terminal_wrapper.open()
      
      local env_arg = mock_toggleterm_provider.open:get_call(1).refs[2]
      assert.is_nil(env_arg.CLAUDE_CODE_SSE_PORT)
    end)

    it("should handle provider unavailable gracefully", function()
      mock_toggleterm_provider.is_available = spy.new(function()
        return false
      end)
      
      terminal_wrapper.setup({ provider = "toggleterm" })
      terminal_wrapper.open()
      
      -- Should fall back to native
      assert.spy(mock_native_provider.open).was_called(1)
    end)
  end)
end)