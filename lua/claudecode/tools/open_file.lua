--- Tool implementation for opening a file.

local schema = {
  description = "Opens a file in the editor with optional selection by line numbers or text patterns",
  inputSchema = {
    type = "object",
    properties = {
      filePath = {
        type = "string",
        description = "Path to the file to open",
      },
      startLine = {
        type = "integer",
        description = "Optional: Line number to start selection",
      },
      endLine = {
        type = "integer",
        description = "Optional: Line number to end selection",
      },
      startText = {
        type = "string",
        description = "Optional: Text pattern to start selection",
      },
      endText = {
        type = "string",
        description = "Optional: Text pattern to end selection",
      },
    },
    required = { "filePath" },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

--- Handles the openFile tool invocation.
-- Opens a file in the editor with optional selection.
-- @param params table The input parameters for the tool.
-- @field params.filePath string Path to the file to open.
-- @field params.startLine integer (Optional) Line number to start selection.
-- @field params.endLine integer (Optional) Line number to end selection.
-- @field params.startText string (Optional) Text pattern to start selection.
-- @field params.endText string (Optional) Text pattern to end selection.
-- @return table A table with a message indicating success.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(params)
  if not params.filePath then
    error({ code = -32602, message = "Invalid params", data = "Missing filePath parameter" })
  end

  local file_path = vim.fn.expand(params.filePath)

  if vim.fn.filereadable(file_path) == 0 then
    -- Using a generic error code for tool-specific operational errors
    error({ code = -32000, message = "File operation error", data = "File not found: " .. file_path })
  end

  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  -- TODO: Implement selection by line numbers (params.startLine, params.endLine)
  -- TODO: Implement selection by text patterns if params.startText and params.endText are provided.

  return { message = "File opened: " .. file_path }
end

return {
  name = "openFile",
  schema = schema,
  handler = handler,
}
