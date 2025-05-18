-- WebSocket server for Claude Code Neovim integration
local M = {}

-- Server state
M.state = {
  server = nil,
  port = nil,
  clients = {},
  handlers = {},
}

-- Find an available port in the given range
function M.find_available_port(min, _) -- '_' for unused max param
  -- TODO: Implement port scanning logic
  -- For now, return a mock value
  return min
end

-- Initialize the WebSocket server
function M.start(config)
  if M.state.server then
    -- Already running
    return false, "Server already running"
  end

  -- TODO: Implement actual WebSocket server
  -- This is a placeholder that would be replaced with real implementation

  -- Find an available port
  local port = M.find_available_port(config.port_range.min, config.port_range.max)

  if not port then
    return false, "No available ports found"
  end

  -- Store the port in state
  M.state.port = port

  -- Mock server object for now
  M.state.server = {
    port = port,
    clients = {},
  }

  -- Register message handlers
  M.register_handlers()

  return true, port
end

-- Stop the WebSocket server
function M.stop()
  if not M.state.server then
    -- Not running
    return false, "Server not running"
  end

  -- TODO: Implement actual WebSocket server shutdown
  -- This is a placeholder

  -- Reset state
  M.state.server = nil
  M.state.port = nil
  M.state.clients = {}

  return true
end

-- Register message handlers
function M.register_handlers()
  -- TODO: Implement message handler registration
  -- These would be functions that handle specific message types

  -- Example handlers:
  M.state.handlers = {
    ["mcp.connect"] = function(_, _) -- '_' for unused args
      -- Handle connection handshake
      -- TODO: Implement
    end,

    ["mcp.tool.invoke"] = function(_, _) -- '_' for unused args
      -- Handle tool invocation
      -- TODO: Implement by dispatching to tool implementations
    end,
  }
end

-- Send a message to a client
function M.send(_, method, params) -- '_' for unused client param
  -- TODO: Implement sending WebSocket message
  -- This is a placeholder

  -- Structure what would be sent (commented out to avoid unused var warning)
  -- local message = {
  --   jsonrpc = "2.0",
  --   method = method,
  --   params = params,
  -- }

  -- Mock sending logic
  -- In real implementation, this would send the JSON-encoded message
  -- to the WebSocket client

  return true
end

-- Send a response to a client
function M.send_response(_, id, result, error_data) -- '_' for unused client param
  -- TODO: Implement sending WebSocket response
  -- This is a placeholder

  -- Structure what would be sent (but don't store it to avoid unused var warning)
  -- Just show what we would do
  if error_data then
    -- Would create: { jsonrpc = "2.0", id = id, error = error_data }
  else
    -- Would create: { jsonrpc = "2.0", id = id, result = result }
  end

  -- Mock sending logic
  return true
end

-- Broadcast a message to all connected clients
function M.broadcast(method, params)
  -- TODO: Implement broadcasting to all clients
  -- This is a placeholder

  for _, client in pairs(M.state.clients) do
    M.send(client, method, params)
  end

  return true
end

return M
