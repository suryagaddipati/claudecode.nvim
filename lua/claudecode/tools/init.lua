-- Tool implementation for Claude Code Neovim integration
local M = {}

-- Tool registry
M.tools = {}

-- Initialize tools
function M.setup(server)
  M.server = server

  -- Register all tools
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

-- Register all tools
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
  M.register("close_tab", nil, M.close_tab)
end

-- Register a tool with optional schema
function M.register(name, schema, handler)
  M.tools[name] = {
    handler = handler,
    schema = schema,
  }
end

-- Handle tool invocation
function M.handle_invoke(_, params) -- '_' for unused client param
  local tool_name = params.name
  local input = params.arguments

  -- Check if tool exists
  if not M.tools[tool_name] then
    return {
      error = {
        code = -32601,
        message = "Tool not found: " .. tool_name,
      },
    }
  end

  -- Execute the tool handler
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

-- Tool: Open a file
function M.open_file(params)
  -- Validate parameters
  if not params.filePath then
    return {
      content = {
        {
          type = "text",
          text = "Error: Missing filePath parameter",
        },
      },
    }
  end

  -- Expand path if needed
  local file_path = vim.fn.expand(params.filePath)

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    return {
      content = {
        {
          type = "text",
          text = "Error: File not found: " .. file_path,
        },
      },
    }
  end

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  -- Handle selection if specified (commented to avoid empty branch warning)
  -- if params.startText and params.endText then
  --   -- TODO: Implement selection by text patterns
  -- end

  return {
    content = {
      {
        type = "text",
        text = "File opened: " .. file_path,
      },
    },
  }
end

-- Tool: Get diagnostics
function M.get_diagnostics(_) -- '_' for unused params
  -- Check if LSP is available
  if not vim.lsp then
    return {
      content = {
        {
          type = "text",
          text = "LSP not available",
        },
      },
    }
  end

  -- Get diagnostics for all buffers
  local all_diagnostics = vim.diagnostic.get()

  -- Format diagnostics
  local result = {}
  for _, diagnostic in ipairs(all_diagnostics) do
    table.insert(result, {
      file = vim.api.nvim_buf_get_name(diagnostic.bufnr),
      line = diagnostic.lnum,
      character = diagnostic.col,
      severity = diagnostic.severity,
      message = diagnostic.message,
      source = diagnostic.source,
    })
  end

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode(result),
      },
    },
  }
end

-- Tool: Get open editors
function M.get_open_editors(_params) -- Prefix unused params with underscore
  local editors = {}

  -- Get list of all buffers
  local buffers = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buffers) do
    -- Only include loaded, listed buffers with a file path
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.fn.buflisted(bufnr) == 1 then
      local file_path = vim.api.nvim_buf_get_name(bufnr)

      -- Skip empty file paths
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
    content = {
      {
        type = "text",
        text = vim.json.encode(editors),
      },
    },
  }
end

-- Tool: Get workspace folders
function M.get_workspace_folders(_) -- '_' for unused params
  -- Get current working directory
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
    content = {
      {
        type = "text",
        text = vim.json.encode(folders),
      },
    },
  }
end

-- Tool: Get current selection
function M.get_current_selection(_) -- '_' for unused params
  -- Get selection from selection module
  -- This is a placeholder; in the real implementation,
  -- this would call into the selection module

  local selection = require("claudecode.selection").get_latest_selection()

  if not selection then
    return {
      content = {
        {
          type = "text",
          text = "No selection available",
        },
      },
    }
  end

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode(selection),
      },
    },
  }
end

-- Tool: Get latest selection
function M.get_latest_selection(_) -- '_' for unused params
  -- Same as get_current_selection for now
  return M.get_current_selection(_)
end

-- Tool: Check if document has unsaved changes
function M.check_document_dirty(params)
  -- Validate parameters
  if not params.filePath then
    return {
      content = {
        {
          type = "text",
          text = "Error: Missing filePath parameter",
        },
      },
    }
  end

  -- Find buffer for the file path
  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      content = {
        {
          type = "text",
          text = "Error: File not open in editor: " .. params.filePath,
        },
      },
    }
  end

  -- Check if buffer is modified
  local is_dirty = vim.api.nvim_buf_get_option(bufnr, "modified")

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode({ isDirty = is_dirty }),
      },
    },
  }
end

-- Tool: Save a document
function M.save_document(params)
  -- Validate parameters
  if not params.filePath then
    return {
      content = {
        {
          type = "text",
          text = "Error: Missing filePath parameter",
        },
      },
    }
  end

  -- Find buffer for the file path
  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      content = {
        {
          type = "text",
          text = "Error: File not open in editor: " .. params.filePath,
        },
      },
    }
  end

  -- Save the buffer
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("write")
  end)

  return {
    content = {
      {
        type = "text",
        text = "File saved: " .. params.filePath,
      },
    },
  }
end

-- Tool: Open a diff view
function M.open_diff(params)
  -- Enhanced parameter validation
  local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }
  for _, param in ipairs(required_params) do
    if not params[param] then
      return {
        content = {
          {
            type = "text",
            text = "Error: Missing required parameter: " .. param,
          },
        },
        isError = true,
      }
    end
  end

  -- Use the diff module
  local diff = require("claudecode.diff")

  local success, result = pcall(function()
    return diff.open_diff(params.old_file_path, params.new_file_path, params.new_file_contents, params.tab_name)
  end)

  if not success then
    return {
      content = {
        {
          type = "text",
          text = "Error opening diff: " .. tostring(result),
        },
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
          result.provider,
          result.tab_name,
          params.old_file_path,
          params.new_file_path
        ),
      },
    },
  }
end

-- Tool: Close a tab
function M.close_tab(params)
  -- Validate parameters
  if not params.tab_name then
    return {
      content = {
        {
          type = "text",
          text = "Error: Missing tab_name parameter",
        },
      },
    }
  end

  -- Find buffer with tab_name
  local bufnr = vim.fn.bufnr(params.tab_name)

  if bufnr == -1 then
    return {
      content = {
        {
          type = "text",
          text = "Error: Tab not found: " .. params.tab_name,
        },
      },
    }
  end

  -- Close the buffer
  vim.api.nvim_buf_delete(bufnr, { force = false })

  return {
    content = {
      {
        type = "text",
        text = "Tab closed: " .. params.tab_name,
      },
    },
  }
end

return M
