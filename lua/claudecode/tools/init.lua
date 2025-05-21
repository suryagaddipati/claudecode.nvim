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

-- Register all tools
function M.register_all()
  -- TODO: Load specific tool implementations
  -- This is a placeholder for now

  -- Example tool registrations
  M.register("openFile", M.open_file)
  M.register("getDiagnostics", M.get_diagnostics)
  M.register("getOpenEditors", M.get_open_editors)
  M.register("getWorkspaceFolders", M.get_workspace_folders)
  M.register("getCurrentSelection", M.get_current_selection)
  M.register("getLatestSelection", M.get_latest_selection)
  M.register("checkDocumentDirty", M.check_document_dirty)
  M.register("saveDocument", M.save_document)
  M.register("openDiff", M.open_diff)
  M.register("close_tab", M.close_tab)
end

-- Register a tool
function M.register(name, handler)
  M.tools[name] = handler
end

-- Handle tool invocation
function M.handle_invoke(_, params) -- '_' for unused client param
  local tool_name = params.name
  local input = params.input

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
  local success, result = pcall(M.tools[tool_name], input)

  if not success then
    return {
      error = {
        code = -32603,
        message = "Tool execution failed: " .. (result or "unknown error"),
      },
    }
  end

  return {
    result = {
      content = result,
    },
  }
end

-- Tool: Open a file
function M.open_file(params)
  -- Validate parameters
  if not params.filePath then
    return { type = "text", text = "Error: Missing filePath parameter" }
  end

  -- Expand path if needed
  local file_path = vim.fn.expand(params.filePath)

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    return {
      type = "text",
      text = "Error: File not found: " .. file_path,
    }
  end

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  -- Handle selection if specified (commented to avoid empty branch warning)
  -- if params.startText and params.endText then
  --   -- TODO: Implement selection by text patterns
  -- end

  return {
    type = "text",
    text = "File opened: " .. file_path,
  }
end

-- Tool: Get diagnostics
function M.get_diagnostics(_) -- '_' for unused params
  -- Check if LSP is available
  if not vim.lsp then
    return {
      type = "text",
      text = "LSP not available",
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
    type = "json",
    json = result,
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
    type = "json",
    json = editors,
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
    type = "json",
    json = folders,
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
      type = "text",
      text = "No selection available",
    }
  end

  return {
    type = "json",
    json = selection,
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
      type = "text",
      text = "Error: Missing filePath parameter",
    }
  end

  -- Find buffer for the file path
  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      type = "text",
      text = "Error: File not open in editor: " .. params.filePath,
    }
  end

  -- Check if buffer is modified
  local is_dirty = vim.api.nvim_buf_get_option(bufnr, "modified")

  return {
    type = "json",
    json = { isDirty = is_dirty },
  }
end

-- Tool: Save a document
function M.save_document(params)
  -- Validate parameters
  if not params.filePath then
    return {
      type = "text",
      text = "Error: Missing filePath parameter",
    }
  end

  -- Find buffer for the file path
  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    return {
      type = "text",
      text = "Error: File not open in editor: " .. params.filePath,
    }
  end

  -- Save the buffer
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("write")
  end)

  return {
    type = "text",
    text = "File saved: " .. params.filePath,
  }
end

-- Tool: Open a diff view
function M.open_diff(params)
  -- Validate parameters
  if not params.old_file_path or not params.new_file_contents then
    return {
      type = "text",
      text = "Error: Missing required parameters",
    }
  end

  -- TODO: Implement diff view
  -- This would involve creating a temporary file with new_file_contents
  -- and opening a diff view with the old file

  return {
    type = "text",
    text = "Diff opened",
  }
end

-- Tool: Close a tab
function M.close_tab(params)
  -- Validate parameters
  if not params.tab_name then
    return {
      type = "text",
      text = "Error: Missing tab_name parameter",
    }
  end

  -- Find buffer with tab_name
  local bufnr = vim.fn.bufnr(params.tab_name)

  if bufnr == -1 then
    return {
      type = "text",
      text = "Error: Tab not found: " .. params.tab_name,
    }
  end

  -- Close the buffer
  vim.api.nvim_buf_delete(bufnr, { force = false })

  return {
    type = "text",
    text = "Tab closed: " .. params.tab_name,
  }
end

return M
