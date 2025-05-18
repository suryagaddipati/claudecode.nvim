-- Simple server module tests

-- Create minimal vim mock if it doesn't exist
if not _G.vim then
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
end

describe("Server module", function()
  local server

  -- Set up before each test
  setup(function()
    -- Reset the module
    package.loaded["claudecode.server"] = nil

    -- Load module
    server = require("claudecode.server")
  end)

  -- Clean up after each test
  teardown(function()
    if server.state.server then
      server.stop()
    end
  end)

  it("should have an empty initial state", function()
    assert.is_table(server.state)
    assert.is_nil(server.state.server)
    assert.is_nil(server.state.port)
    assert.is_table(server.state.clients)
    assert.is_table(server.state.handlers)
  end)

  it("should find an available port", function()
    local port = server.find_available_port(10000, 65535)

    assert.is_number(port)
    assert.is_true(port >= 10000)
    assert.is_true(port <= 65535)
  end)

  it("should start and stop the server", function()
    local config = {
      port_range = {
        min = 10000,
        max = 65535,
      },
    }

    -- Start the server
    local start_success, result = server.start(config)

    assert.is_true(start_success)
    assert.is_number(result)
    assert.is_not_nil(server.state.server)
    assert.is_not_nil(server.state.port)

    -- Stop the server
    local stop_success = server.stop()

    assert.is_true(stop_success)
    assert.is_nil(server.state.server)
    assert.is_nil(server.state.port)
    assert.is_table(server.state.clients)
    assert.equals(0, #server.state.clients)
  end)

  it("should not stop the server if not running", function()
    -- Ensure server is not running
    if server.state.server then
      server.stop()
    end

    local success, error = server.stop()

    assert.is_false(success)
    assert.equals("Server not running", error)
  end)
end)
