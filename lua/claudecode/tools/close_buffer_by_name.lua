--- Tool implementation for closing a buffer by its name.

local function handler(params)
  if not params.buffer_name then
    error({ code = -32602, message = "Invalid params", data = "Missing buffer_name parameter" })
  end

  local bufnr = vim.fn.bufnr(params.buffer_name)

  if bufnr == -1 then
    error({
      code = -32000,
      message = "Buffer operation error",
      data = "Buffer not found: " .. params.buffer_name,
    })
  end

  local success, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })

  if not success then
    error({
      code = -32000,
      message = "Buffer operation error",
      data = "Failed to close buffer " .. params.buffer_name .. ": " .. tostring(err),
    })
  end

  return { message = "Buffer closed: " .. params.buffer_name }
end

return {
  name = "closeBufferByName",
  schema = nil, -- Internal tool
  handler = handler,
}
