require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: close_buffer_by_name", function()
  local close_buffer_by_name_handler

  before_each(function()
    package.loaded["claudecode.tools.close_buffer_by_name"] = nil
    close_buffer_by_name_handler = require("claudecode.tools.close_buffer_by_name").handler

    _G.vim = _G.vim or {}
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.api = _G.vim.api or {}

    _G.vim.fn.bufnr = spy.new(function(bufferName)
      if bufferName == "/path/to/closable_buffer.lua" then
        return 1
      end
      if bufferName == "another_buffer.txt" then
        return 2
      end
      return -1 -- Buffer not found
    end)

    _G.vim.api.nvim_buf_delete = spy.new(function(bufnr, opts)
      -- Simulate success, can add error simulation if needed
      if bufnr ~= 1 and bufnr ~= 2 then
        error("nvim_buf_delete called with unexpected bufnr: " .. tostring(bufnr))
      end
    end)
  end)

  after_each(function()
    package.loaded["claudecode.tools.close_buffer_by_name"] = nil
    _G.vim.fn.bufnr = nil
    _G.vim.api.nvim_buf_delete = nil
  end)

  it("should error if buffer_name parameter is missing", function()
    local success, err = pcall(close_buffer_by_name_handler, {})
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32602)
    assert_contains(err.data, "Missing buffer_name parameter")
  end)

  it("should error if buffer is not found", function()
    local params = { buffer_name = "/path/to/non_existent_buffer.py" }
    local success, err = pcall(close_buffer_by_name_handler, params)
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000)
    assert_contains(err.data, "Buffer not found: /path/to/non_existent_buffer.py")
    assert.spy(_G.vim.fn.bufnr).was_called_with("/path/to/non_existent_buffer.py")
  end)

  it("should call nvim_buf_delete with correct parameters on success", function()
    local params = { buffer_name = "/path/to/closable_buffer.lua" }
    local success, result = pcall(close_buffer_by_name_handler, params)

    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.message).to_be("Buffer closed: /path/to/closable_buffer.lua")

    assert.spy(_G.vim.fn.bufnr).was_called_with("/path/to/closable_buffer.lua")
    assert.spy(_G.vim.api.nvim_buf_delete).was_called_with(1, { force = false })
  end)

  it("should propagate error if nvim_buf_delete fails", function()
    _G.vim.api.nvim_buf_delete = spy.new(function(bufnr, opts)
      error("Simulated nvim_buf_delete failure")
    end)
    local params = { buffer_name = "another_buffer.txt" }
    local success, err = pcall(close_buffer_by_name_handler, params)

    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Buffer operation error")
    assert_contains(err.data, "Failed to close buffer")
    assert_contains(err.data, "Simulated nvim_buf_delete failure")
  end)
end)
