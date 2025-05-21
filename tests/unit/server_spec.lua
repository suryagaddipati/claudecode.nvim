-- Unit tests for WebSocket server module
-- luacheck: globals expect
require("tests.busted_setup")

describe("WebSocket Server", function()
  local server

  -- Set up before each test
  local function setup()
    -- Reset loaded modules
    package.loaded["claudecode.server"] = nil

    -- Load the module under test
    server = require("claudecode.server")
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

  it("should find an available port", function()
    local min_port = 10000
    local max_port = 65535

    local port = server.find_available_port(min_port, max_port)

    -- Instead of expecting a specific port, just check if it's in the valid range
    expect(port >= min_port and port <= max_port).to_be_true()
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
    expect(type(server.state.handlers["mcp.connect"])).to_be("function") -- Function, not table
    expect(type(server.state.handlers["mcp.tool.invoke"])).to_be("function") -- Function, not table
  end)

  it("should send message to client", function()
    -- Mock client
    local client = {}

    local method = "test_method"
    local params = { foo = "bar" }

    local success = server.send(client, method, params)

    expect(success).to_be_true()
  end)

  it("should send response to client", function()
    -- Mock client
    local client = {}

    local id = "test_id"
    local result = { foo = "bar" }

    local success = server.send_response(client, id, result)

    expect(success).to_be_true()
  end)

  it("should broadcast to all clients", function()
    -- Add mock clients
    server.state.clients = {
      client1 = {},
      client2 = {},
    }

    local method = "test_method"
    local params = { foo = "bar" }

    local success = server.broadcast(method, params)

    expect(success).to_be_true()
  end)

  -- Clean up after all tests
  teardown()
end)
