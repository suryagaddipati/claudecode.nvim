-- Tool implementation for Claude Code Neovim integration
local M = {}

M.tools = {}

function M.setup(server)
  M.server = server

  M.register_all()
end

--- Get the complete tool list for MCP tools/list handler
function M.get_tool_list()
  local tool_list = {}

  for name, tool_data in pairs(M.tools) do
    -- Only include tools that have schemas (are meant to be exposed via MCP)
    if tool_data.schema then
      local tool_def = {
        name = name,
        description = tool_data.schema.description,
        inputSchema = tool_data.schema.inputSchema,
      }
      table.insert(tool_list, tool_def)
    end
  end

  return tool_list
end

function M.register_all()
  -- Register MCP-exposed tools with schemas
  M.register("openFile", {
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
  }, M.open_file)

  M.register("getCurrentSelection", {
    description = "Get the current text selection in the editor",
    inputSchema = {
      type = "object",
      additionalProperties = false,
      ["$schema"] = "http://json-schema.org/draft-07/schema#",
    },
  }, M.get_current_selection)

  M.register("getOpenEditors", {
    description = "Get list of currently open files",
    inputSchema = {
      type = "object",
      additionalProperties = false,
      ["$schema"] = "http://json-schema.org/draft-07/schema#",
    },
  }, M.get_open_editors)

  M.register("openDiff", {
    description = "Open a diff view comparing old file content with new file content",
    inputSchema = {
      type = "object",
      properties = {
        old_file_path = {
          type = "string",
          description = "Path to the old file to compare",
        },
        new_file_path = {
          type = "string",
          description = "Path to the new file to compare",
        },
        new_file_contents = {
          type = "string",
          description = "Contents for the new file version",
        },
        tab_name = {
          type = "string",
          description = "Name for the diff tab/view",
        },
      },
      required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
      additionalProperties = false,
      ["$schema"] = "http://json-schema.org/draft-07/schema#",
    },
  }, M.open_diff)

  -- Register internal tools without schemas (not exposed via MCP)
  M.register("getDiagnostics", nil, M.get_diagnostics)
  M.register("getWorkspaceFolders", nil, M.get_workspace_folders)
  M.register("getLatestSelection", nil, M.get_latest_selection)
  M.register("checkDocumentDirty", nil, M.check_document_dirty)
  M.register("saveDocument", nil, M.save_document)
  M.register("closeBufferByName", nil, M.close_buffer_by_name)
end

function M.register(name, schema, handler)
  M.tools[name] = {
    handler = handler,
    schema = schema,
  }
end

function M.handle_invoke(_, params) -- '_' for unused client param
  local tool_name = params.name
  local input = params.arguments

  if not M.tools[tool_name] then
    return {
      error = {
        code = -32601,
        message = "Tool not found: " .. tool_name,
      },
    }
  end

  local tool_data = M.tools[tool_name]
  local success, result = pcall(tool_data.handler, input)

  if not success then
    return {
      error = {
        code = -32603,
        message = "Tool execution failed: " .. (result or "unknown error"),
      },
    }
  end

  return {
    result = result,
  }
end

function M.open_file(params)
  if not params.filePath then
    return {
      content = { { type = "text", text = "Error: Missing filePath parameter" } },
      isError = true,
    }
  end

  local file_path = vim.fn.expand(params.filePath)

  if vim.fn.filereadable(file_path) == 0 then
    return {
      content = { { type = "text", text = "Error: File not found: " .. file_path } },
      isError = true,
    }
  end

  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  -- TODO: Implement selection by text patterns if params.startText and params.endText are provided.

  return {
    content = { { type = "text", text = "File opened: " .. file_path } },
    isError = false,
  }
end

function M.get_diagnostics(_) -- '_' for unused params
  if not vim.lsp or not vim.diagnostic or not vim.diagnostic.get then
    return {
      content = { { type = "text", text = "LSP or vim.diagnostic.get not available" } },
      isError = true, -- Consider this an error or a specific state
    }
  end

  local all_diagnostics = vim.diagnostic.get()

  local formatted_diagnostics = {}
  for _, diagnostic in ipairs(all_diagnostics) do
    table.insert(formatted_diagnostics, {
      file = vim.api.nvim_buf_get_name(diagnostic.bufnr),
      line = diagnostic.lnum,
      character = diagnostic.col,
      severity = diagnostic.severity,
      message = diagnostic.message,
      source = diagnostic.source,
    })
  end

  return {
    content = { { type = "text", text = vim.json.encode({ diagnostics = formatted_diagnostics }) } },
    isError = false,
  }
end

function M.get_open_editors(_params) -- Prefix unused params with underscore
  local editors = {}

  local buffers = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buffers) do
    -- Only include loaded, listed buffers with a file path
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.fn.buflisted(bufnr) == 1 then
      local file_path = vim.api.nvim_buf_get_name(bufnr)

      if file_path and file_path ~= "" then
        table.insert(editors, {
          filePath = file_path,
          fileUrl = "file://" .. file_path,
          isDirty = vim.api.nvim_buf_get_option(bufnr, "modified"),
        })
      end
    end
  end

  return {
    content = { { type = "text", text = vim.json.encode({ editors = editors }) } },
    isError = false,
  }
end

function M.get_workspace_folders(_) -- '_' for unused params
  local cwd = vim.fn.getcwd()

  -- For now, just return the current working directory
  -- TODO: Integrate with LSP workspace folders if available

  local folders = {
    {
      name = vim.fn.fnamemodify(cwd, ":t"),
      uri = "file://" .. cwd,
      path = cwd,
    },
  }

  return {
    content = { { type = "text", text = vim.json.encode({ workspaceFolders = folders }) } },
    isError = false,
  }
end

function M.get_current_selection(_) -- '_' for unused params
  -- Placeholder: delegates to selection module
  local selection = require("claudecode.selection").get_latest_selection()

  if not selection then
    return {
      content = { { type = "text", text = "No selection available" } },
      isError = true, -- Or false, depending on whether "no selection" is an error or valid state
    }
  end

  return {
    content = { { type = "text", text = vim.json.encode(selection) } },
    isError = false,
  }
end

function M.get_latest_selection(_) -- '_' for unused params
  -- Same as get_current_selection for now
  return M.get_current_selection(_)
end

function M.check_document_dirty(params)
  if not params.filePath then
    return {
      content = { { type = "text", text = "Error: Missing filePath parameter" } },
      isError = true,
    }
  end

  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      content = { { type = "text", text = "Error: File not open in editor: " .. params.filePath } },
      isError = true,
    }
  end

  local is_dirty = vim.api.nvim_buf_get_option(bufnr, "modified")

  return {
    content = { { type = "text", text = vim.json.encode({ isDirty = is_dirty }) } },
    isError = false,
  }
end

function M.save_document(params)
  if not params.filePath then
    return {
      content = { { type = "text", text = "Error: Missing filePath parameter" } },
      isError = true,
    }
  end

  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      content = { { type = "text", text = "Error: File not open in editor: " .. params.filePath } },
      isError = true,
    }
  end

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("write")
  end)

  return {
    content = { { type = "text", text = "File saved: " .. params.filePath } },
    isError = false,
  }
end

function M.open_diff(params)
  local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }
  for _, param_name in ipairs(required_params) do
    if not params[param_name] then
      return {
        content = { { type = "text", text = "Error: Missing required parameter: " .. param_name } },
        isError = true,
      }
    end
  end

  local diff_module = require("claudecode.diff")

  local success, result_data = pcall(function()
    return diff_module.open_diff(params.old_file_path, params.new_file_path, params.new_file_contents, params.tab_name)
  end)

  if not success then
    -- result_data here is the error message from pcall
    return {
      content = { { type = "text", text = "Error opening diff: " .. tostring(result_data) } },
      isError = true,
    }
  end

  -- result_data from diff.open_diff is a table like { provider = "...", tab_name = "...", success = true/false, error = "..." }
  if not result_data.success then
    return {
      content = {
        { type = "text", text = "Error from diff provider: " .. (result_data.error or "Unknown diff error") },
      },
      isError = true,
    }
  end

  return {
    content = {
      {
        type = "text",
        text = string.format(
          "Diff opened using %s provider: %s (%s vs %s)",
          result_data.provider or "unknown",
          result_data.tab_name or "untitled",
          params.old_file_path,
          params.new_file_path
        ),
      },
    },
    isError = false,
  }
end

function M.close_buffer_by_name(params)
  if not params.buffer_name then
    return {
      content = { { type = "text", text = "Error: Missing buffer_name parameter" } },
      isError = true,
    }
  end

  local bufnr = vim.fn.bufnr(params.buffer_name)

  if bufnr == -1 then
    return {
      content = { { type = "text", text = "Error: Buffer not found: " .. params.buffer_name } },
      isError = true,
    }
  end

  vim.api.nvim_buf_delete(bufnr, { force = false })

  return {
    content = { { type = "text", text = "Buffer closed: " .. params.buffer_name } },
    isError = false,
  }
end

return M
