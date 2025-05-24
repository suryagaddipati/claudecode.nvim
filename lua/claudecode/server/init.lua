---@brief WebSocket server for Claude Code Neovim integration
local claudecode_main = require("claudecode") -- Added for version access
local logger = require("claudecode.logger")
local tcp_server = require("claudecode.server.tcp")
local tools = require("claudecode.tools.init") -- Added: Require the tools module

local MCP_PROTOCOL_VERSION = "2024-11-05"

local M = {}

---@class ServerState
---@field server table|nil The TCP server instance
---@field port number|nil The port server is running on
---@field clients table A list of connected clients
---@field handlers table Message handlers by method name
---@field ping_timer table|nil Timer for sending pings
M.state = {
  server = nil,
  port = nil,
  clients = {},
  handlers = {},
  ping_timer = nil,
}

---@brief Initialize the WebSocket server
---@param config table Configuration options
---@return boolean success Whether server started successfully
---@return number|string port_or_error Port number or error message
function M.start(config)
  if M.state.server then
    return false, "Server already running"
  end

  M.register_handlers()

  tools.setup(M)

  local callbacks = {
    on_message = function(client, message)
      M._handle_message(client, message)
    end,
    on_connect = function(client)
      M.state.clients[client.id] = client
      logger.debug("server", "WebSocket client connected:", client.id)
    end,
    on_disconnect = function(client, code, reason)
      M.state.clients[client.id] = nil
      logger.debug(
        "server",
        "WebSocket client disconnected:",
        client.id,
        "(code:",
        code,
        ", reason:",
        (reason or "N/A") .. ")"
      )
    end,
    on_error = function(error_msg)
      logger.error("server", "WebSocket server error:", error_msg)
    end,
  }

  local server, error_msg = tcp_server.create_server(config, callbacks)
  if not server then
    return false, error_msg or "Unknown server creation error"
  end

  M.state.server = server
  M.state.port = server.port

  M.state.ping_timer = tcp_server.start_ping_timer(server, 30000) -- Start ping timer to keep connections alive

  return true, server.port
end

---@brief Stop the WebSocket server
---@return boolean success Whether server stopped successfully
---@return string|nil error_message Error message if any
function M.stop()
  if not M.state.server then
    return false, "Server not running"
  end

  if M.state.ping_timer then
    M.state.ping_timer:stop()
    M.state.ping_timer:close()
    M.state.ping_timer = nil
  end

  tcp_server.stop_server(M.state.server)

  M.state.server = nil
  M.state.port = nil
  M.state.clients = {}

  return true
end

---@brief Handle incoming WebSocket message
---@param client table The client that sent the message
---@param message string The JSON-RPC message
function M._handle_message(client, message)
  local success, parsed = pcall(vim.json.decode, message)
  if not success then
    M.send_response(client, nil, nil, {
      code = -32700,
      message = "Parse error",
      data = "Invalid JSON",
    })
    return
  end

  if type(parsed) ~= "table" or parsed.jsonrpc ~= "2.0" then
    M.send_response(client, parsed.id, nil, {
      code = -32600,
      message = "Invalid Request",
      data = "Not a valid JSON-RPC 2.0 request",
    })
    return
  end

  if parsed.id then
    M._handle_request(client, parsed)
  else
    M._handle_notification(client, parsed)
  end
end

---@brief Handle JSON-RPC request (requires response)
---@param client table The client that sent the request
---@param request table The parsed JSON-RPC request
function M._handle_request(client, request)
  local method = request.method
  local params = request.params or {}
  local id = request.id

  local handler = M.state.handlers[method]
  if not handler then
    M.send_response(client, id, nil, {
      code = -32601,
      message = "Method not found",
      data = "Unknown method: " .. tostring(method),
    })
    return
  end

  local success, result, error_data = pcall(handler, client, params)
  if success then
    if error_data then
      M.send_response(client, id, nil, error_data)
    else
      M.send_response(client, id, result, nil)
    end
  else
    M.send_response(client, id, nil, {
      code = -32603,
      message = "Internal error",
      data = tostring(result), -- result contains error message when pcall fails
    })
  end
end

---@brief Handle JSON-RPC notification (no response)
---@param client table The client that sent the notification
---@param notification table The parsed JSON-RPC notification
function M._handle_notification(client, notification)
  local method = notification.method
  local params = notification.params or {}

  local handler = M.state.handlers[method]
  if handler then
    pcall(handler, client, params)
  end
end

---@brief Register message handlers for the server
function M.register_handlers()
  M.state.handlers = {
    ["initialize"] = function(client, params) -- Renamed from mcp.connect
      return {
        protocolVersion = MCP_PROTOCOL_VERSION,
        capabilities = {
          logging = vim.empty_dict(), -- Ensure this is an object {} not an array []
          prompts = { listChanged = true },
          resources = { subscribe = true, listChanged = true },
          tools = { listChanged = true },
        },
        serverInfo = {
          name = "claudecode-neovim",
          version = claudecode_main.version:string(),
        },
      }
    end,

    ["notifications/initialized"] = function(client, params) -- Added handler for initialized notification
    end,

    ["prompts/list"] = function(client, params) -- Added handler for prompts/list
      return {
        prompts = {}, -- This will be encoded as an empty JSON array
      }
    end,

    ["tools/list"] = function(_client, _params)
      return {
        tools = tools.get_tool_list(),
      }
    end,

    ["tools/call"] = function(client, params)
      local result_or_error_table = tools.handle_invoke(client, params)

      if result_or_error_table.error then
        return nil, result_or_error_table.error
      elseif result_or_error_table.result then
        return result_or_error_table.result, nil
      else
        -- Should not happen if tools.handle_invoke behaves correctly
        return nil,
          {
            code = -32603,
            message = "Internal error",
            data = "Tool handler returned unexpected format",
          }
      end
    end,
  }
end

---@brief Send a message to a client
---@param client table The client to send to
---@param method string The method name
---@param params table|nil The parameters to send
---@return boolean success Whether message was sent successfully
function M.send(client, method, params)
  if not M.state.server then
    return false
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }

  local json_message = vim.json.encode(message)
  tcp_server.send_to_client(M.state.server, client.id, json_message)
  return true
end

---@brief Send a response to a client
---@param client table The client to send to
---@param id number|string|nil The request ID to respond to
---@param result any|nil The result data if successful
---@param error_data table|nil The error data if failed
---@return boolean success Whether response was sent successfully
function M.send_response(client, id, result, error_data)
  if not M.state.server then
    return false
  end

  local response = {
    jsonrpc = "2.0",
    id = id,
  }

  if error_data then
    response.error = error_data
  else
    response.result = result
  end

  local json_response = vim.json.encode(response)
  tcp_server.send_to_client(M.state.server, client.id, json_response)
  return true
end

---@brief Broadcast a message to all connected clients
---@param method string The method name
---@param params table|nil The parameters to send
---@return boolean success Whether broadcast was successful
function M.broadcast(method, params)
  if not M.state.server then
    return false
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }

  local json_message = vim.json.encode(message)
  tcp_server.broadcast(M.state.server, json_message)
  return true
end

---@brief Get server status information
---@return table status Server status information
function M.get_status()
  if not M.state.server then
    return {
      running = false,
      port = nil,
      client_count = 0,
    }
  end

  return {
    running = true,
    port = M.state.port,
    client_count = tcp_server.get_client_count(M.state.server),
    clients = tcp_server.get_clients_info(M.state.server),
  }
end

return M
