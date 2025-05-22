---@brief WebSocket client connection management
local frame = require("claudecode.server.frame")
local handshake = require("claudecode.server.handshake")

local M = {}

---@class WebSocketClient
---@field id string Unique client identifier
---@field tcp_handle table The vim.loop TCP handle
---@field state string Connection state: "connecting", "connected", "closing", "closed"
---@field buffer string Incoming data buffer
---@field handshake_complete boolean Whether WebSocket handshake is complete
---@field last_ping number Timestamp of last ping sent
---@field last_pong number Timestamp of last pong received

---@brief Create a new WebSocket client
---@param tcp_handle table The vim.loop TCP handle
---@return WebSocketClient client The client object
function M.create_client(tcp_handle)
  local client_id = tostring(tcp_handle):gsub("userdata: ", "client_")

  local client = {
    id = client_id,
    tcp_handle = tcp_handle,
    state = "connecting",
    buffer = "",
    handshake_complete = false,
    last_ping = 0,
    last_pong = vim.loop.now(),
  }

  return client
end

---@brief Process incoming data for a client
---@param client WebSocketClient The client object
---@param data string The incoming data
---@param on_message function Callback for complete messages: function(client, message_text)
---@param on_close function Callback for client close: function(client, code, reason)
---@param on_error function Callback for errors: function(client, error_msg)
function M.process_data(client, data, on_message, on_close, on_error)
  client.buffer = client.buffer .. data

  if not client.handshake_complete then
    -- Process HTTP handshake
    local complete, request, remaining = handshake.extract_http_request(client.buffer)
    if complete then
      local success, response_from_handshake, _ = handshake.process_handshake(request)

      -- Send handshake response
      client.tcp_handle:write(response_from_handshake, function(err)
        if err then
          on_error(client, "Failed to send handshake response: " .. err)
          return
        end

        if success then
          client.handshake_complete = true
          client.state = "connected"
          client.buffer = remaining

          -- Process any remaining data as WebSocket frames
          if #client.buffer > 0 then
            M.process_data(client, "", on_message, on_close, on_error)
          end
        else
          -- Handshake failed, close connection
          client.state = "closing"
          vim.schedule(function()
            client.tcp_handle:close()
          end)
        end
      end)
    end
    return
  end

  -- Process WebSocket frames
  while #client.buffer >= 2 do -- Minimum frame size
    local parsed_frame, bytes_consumed = frame.parse_frame(client.buffer)

    if not parsed_frame then
      -- Incomplete frame, wait for more data
      break
    end

    -- Validate frame
    local valid, error_msg = frame.validate_frame(parsed_frame)
    if not valid then
      on_error(client, "Invalid WebSocket frame: " .. error_msg)
      M.close_client(client, 1002, "Protocol error")
      return
    end

    -- Remove processed bytes from buffer
    client.buffer = client.buffer:sub(bytes_consumed + 1)

    -- Handle frame based on opcode
    if parsed_frame.opcode == frame.OPCODE.TEXT then
      -- Text message
      vim.schedule(function()
        on_message(client, parsed_frame.payload)
      end)
    elseif parsed_frame.opcode == frame.OPCODE.BINARY then
      -- Binary message (treat as text for JSON-RPC)
      vim.schedule(function()
        on_message(client, parsed_frame.payload)
      end)
    elseif parsed_frame.opcode == frame.OPCODE.CLOSE then
      -- Close frame
      local code = 1000
      local reason = ""

      if #parsed_frame.payload >= 2 then
        local payload = parsed_frame.payload
        code = payload:byte(1) * 256 + payload:byte(2)
        if #payload > 2 then
          reason = payload:sub(3)
        end
      end

      -- Send close frame response if we haven't already
      if client.state == "connected" then
        local close_frame = frame.create_close_frame(code, reason)
        client.tcp_handle:write(close_frame)
        client.state = "closing"
      end

      vim.schedule(function()
        on_close(client, code, reason)
      end)
    elseif parsed_frame.opcode == frame.OPCODE.PING then
      -- Ping frame - respond with pong
      local pong_frame = frame.create_pong_frame(parsed_frame.payload)
      client.tcp_handle:write(pong_frame)
    elseif parsed_frame.opcode == frame.OPCODE.PONG then
      -- Pong frame - update last pong timestamp
      client.last_pong = vim.loop.now()
    elseif parsed_frame.opcode == frame.OPCODE.CONTINUATION then
      -- Continuation frame - for simplicity, we don't support fragmentation
      on_error(client, "Fragmented messages not supported")
      M.close_client(client, 1003, "Unsupported data")
    else
      -- Unknown opcode
      on_error(client, "Unknown WebSocket opcode: " .. parsed_frame.opcode)
      M.close_client(client, 1002, "Protocol error")
    end
  end
end

---@brief Send a text message to a client
---@param client WebSocketClient The client object
---@param message string The message to send
---@param callback function|nil Optional callback: function(err)
function M.send_message(client, message, callback)
  if client.state ~= "connected" then
    if callback then
      callback("Client not connected")
    end
    return
  end

  local text_frame = frame.create_text_frame(message)
  client.tcp_handle:write(text_frame, callback)
end

---@brief Send a ping to a client
---@param client WebSocketClient The client object
---@param data string|nil Optional ping data
function M.send_ping(client, data)
  if client.state ~= "connected" then
    return
  end

  local ping_frame = frame.create_ping_frame(data or "")
  client.tcp_handle:write(ping_frame)
  client.last_ping = vim.loop.now()
end

---@brief Close a client connection
---@param client WebSocketClient The client object
---@param code number|nil Close code (default: 1000)
---@param reason string|nil Close reason
function M.close_client(client, code, reason)
  if client.state == "closed" or client.state == "closing" then
    return
  end

  code = code or 1000
  reason = reason or ""

  if client.handshake_complete then
    -- Send close frame
    local close_frame = frame.create_close_frame(code, reason)
    client.tcp_handle:write(close_frame, function()
      client.state = "closed"
      client.tcp_handle:close()
    end)
  else
    -- Just close the TCP connection
    client.state = "closed"
    client.tcp_handle:close()
  end

  client.state = "closing"
end

---@brief Check if a client connection is alive
---@param client WebSocketClient The client object
---@param timeout number Timeout in milliseconds (default: 30000)
---@return boolean alive True if the client is considered alive
function M.is_client_alive(client, timeout)
  timeout = timeout or 30000 -- 30 seconds default

  if client.state ~= "connected" then
    return false
  end

  local now = vim.loop.now()
  return (now - client.last_pong) < timeout
end

---@brief Get client info for debugging
---@param client WebSocketClient The client object
---@return table info Client information
function M.get_client_info(client)
  return {
    id = client.id,
    state = client.state,
    handshake_complete = client.handshake_complete,
    buffer_size = #client.buffer,
    last_ping = client.last_ping,
    last_pong = client.last_pong,
  }
end

return M
