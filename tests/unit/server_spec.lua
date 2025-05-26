-- Unit tests for WebSocket server module
-- luacheck: globals expect
require("tests.busted_setup")

describe("WebSocket Server", function()
  local server

  -- Set up before each test
  local function setup()
    -- Reset loaded modules
    package.loaded["claudecode.server.init"] = nil -- Also update package.loaded key

    -- Load the module under test
    server = require("claudecode.server.init")
  end

  -- Clean up after each test
  local function teardown()
    -- Ensure server is stopped
    if server.state.server then
      server.stop()
    end
  end

  -- Run setup before each test
  setup()

  it("should have a get_status function", function()
    local status = server.get_status()

    expect(status).to_be_table()
    expect(status.running).to_be_false()
    expect(status.port).to_be_nil()
    expect(status.client_count).to_be(0)
  end)

  it("should start server successfully", function()
    local config = {
      port_range = {
        min = 10000,
        max = 65535,
      },
    }

    local success, port = server.start(config)

    expect(success).to_be_true()
    expect(server.state.server).to_be_table()
    expect(server.state.port).to_be(port)
    expect(port >= config.port_range.min and port <= config.port_range.max).to_be_true()

    -- Clean up
    server.stop()
  end)

  it("should not start server twice", function()
    local config = {
      port_range = {
        min = 10000,
        max = 65535,
      },
    }

    -- Start once
    local success1, _ = server.start(config)
    expect(success1).to_be_true()

    -- Try to start again
    local success2, error2 = server.start(config)
    expect(success2).to_be_false()
    expect(error2).to_be("Server already running")

    -- Clean up
    server.stop()
  end)

  it("should stop server successfully", function()
    local config = {
      port_range = {
        min = 10000,
        max = 65535,
      },
    }

    -- Start server
    server.start(config)

    -- Stop server
    local success, _ = server.stop()

    expect(success).to_be_true()
    expect(server.state.server).to_be_nil()
    expect(server.state.port).to_be_nil()
    expect(server.state.clients).to_be_table()
    expect(#server.state.clients).to_be(0)
  end)

  it("should not stop server if not running", function()
    -- Ensure server is not running
    if server.state.server then
      server.stop()
    end

    -- Try to stop again
    local success, error = server.stop()

    expect(success).to_be_false()
    expect(error).to_be("Server not running")
  end)

  it("should register message handlers", function()
    server.register_handlers()

    expect(server.state.handlers).to_be_table()
    expect(type(server.state.handlers["initialize"])).to_be("function") -- Function, not table
    expect(type(server.state.handlers["tools/list"])).to_be("function") -- Function, not table
  end)

  it("should send message to client", function()
    -- Start server first
    local config = { port_range = { min = 10000, max = 65535 } }
    server.start(config)

    -- Mock client
    local client = { id = "test_client" }

    local method = "test_method"
    local params = { foo = "bar" }

    local success = server.send(client, method, params)

    expect(success).to_be_true()

    -- Clean up
    server.stop()
  end)

  it("should send response to client", function()
    -- Start server first
    local config = { port_range = { min = 10000, max = 65535 } }
    server.start(config)

    -- Mock client
    local client = { id = "test_client" }

    local id = "test_id"
    local result = { foo = "bar" }

    local success = server.send_response(client, id, result)

    expect(success).to_be_true()

    -- Clean up
    server.stop()
  end)

  it("should broadcast to all clients", function()
    -- Start server first
    local config = { port_range = { min = 10000, max = 65535 } }
    server.start(config)

    local method = "test_method"
    local params = { foo = "bar" }

    local success = server.broadcast(method, params)

    expect(success).to_be_true()

    -- Clean up
    server.stop()
  end)

  -- Clean up after all tests
  teardown()
end)
