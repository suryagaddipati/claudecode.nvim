--- Tool implementation for closing a buffer by its name.

local schema = {
  description = "Close a tab/buffer by its tab name",
  inputSchema = {
    type = "object",
    properties = {
      tab_name = {
        type = "string",
        description = "Name of the tab to close",
      },
    },
    required = { "tab_name" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

--- Handles the close_tab tool invocation.
-- Closes a tab/buffer by its tab name.
-- @param params table The input parameters for the tool.
-- @field params.tab_name string Name of the tab to close.
-- @return table A result message indicating success.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(params)
  local log_module_ok, log = pcall(require, "claudecode.logger")
  if not log_module_ok then
    return {
      code = -32603, -- Internal error
      message = "Internal error",
      data = "Failed to load logger module",
    }
  end

  log.debug("close_tab handler called with params: " .. vim.inspect(params))

  if not params.tab_name then
    log.error("Missing required parameter: tab_name")
    return {
      code = -32602, -- Invalid params
      message = "Invalid params",
      data = "Missing required parameter: tab_name",
    }
  end

  -- Extract the actual file name from the tab name
  -- Tab name format: "✻ [Claude Code] README.md (e18e1e) ⧉"
  -- We need to extract "README.md" or the full path
  local tab_name = params.tab_name
  log.debug("Attempting to close tab: " .. tab_name)

  -- Try to find buffer by the tab name first
  local bufnr = vim.fn.bufnr(tab_name)

  if bufnr == -1 then
    -- If not found, try to extract filename from the tab name
    -- Look for pattern like "filename.ext" in the tab name
    local filename = tab_name:match("([%w%.%-_]+%.[%w]+)")
    if filename then
      log.debug("Extracted filename from tab name: " .. filename)
      -- Try to find buffer by filename
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name:match(filename .. "$") then
          bufnr = buf
          log.debug("Found buffer by filename match: " .. buf_name)
          break
        end
      end
    end
  end

  if bufnr == -1 then
    log.error("Buffer not found for tab: " .. tab_name)
    return {
      code = -32000,
      message = "Buffer operation error",
      data = "Buffer not found for tab: " .. tab_name,
    }
  end

  local success, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })

  if not success then
    log.error("Failed to close buffer: " .. tostring(err))
    return {
      code = -32000,
      message = "Buffer operation error",
      data = "Failed to close buffer for tab " .. tab_name .. ": " .. tostring(err),
    }
  end

  log.info("Successfully closed tab: " .. tab_name)
  return { message = "Tab closed: " .. tab_name }
end

return {
  name = "close_tab",
  schema = schema,
  handler = handler,
}
