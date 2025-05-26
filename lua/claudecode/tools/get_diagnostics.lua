--- Tool implementation for getting diagnostics.

--- Handles the getDiagnostics tool invocation.
-- Retrieves diagnostics from Neovim's diagnostic system.
-- @param _params table The input parameters for the tool (currently unused).
-- @return table A table containing the list of diagnostics.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(_params) -- Prefix unused params with underscore
  if not vim.lsp or not vim.diagnostic or not vim.diagnostic.get then
    -- This tool is internal, so returning an error might be too strong.
    -- Returning an empty list or a specific status could be an alternative.
    -- For now, let's align with the error pattern for consistency if the feature is unavailable.
    error({
      code = -32000,
      message = "Feature unavailable",
      data = "LSP or vim.diagnostic.get not available in this Neovim version/configuration.",
    })
  end

  local all_diagnostics = vim.diagnostic.get(0) -- Get for all buffers

  local formatted_diagnostics = {}
  for _, diagnostic in ipairs(all_diagnostics) do
    local file_path = vim.api.nvim_buf_get_name(diagnostic.bufnr)
    -- Ensure we only include diagnostics with valid file paths
    if file_path and file_path ~= "" then
      table.insert(formatted_diagnostics, {
        file = file_path,
        line = diagnostic.lnum, -- 0-indexed from vim.diagnostic.get
        character = diagnostic.col, -- 0-indexed from vim.diagnostic.get
        severity = diagnostic.severity, -- e.g., vim.diagnostic.severity.ERROR
        message = diagnostic.message,
        source = diagnostic.source,
      })
    end
  end

  return { diagnostics = formatted_diagnostics }
end

return {
  name = "getDiagnostics",
  schema = nil, -- Internal tool
  handler = handler,
}
