require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: get_diagnostics", function()
  local get_diagnostics_handler

  before_each(function()
    package.loaded["claudecode.tools.get_diagnostics"] = nil
    get_diagnostics_handler = require("claudecode.tools.get_diagnostics").handler

    _G.vim = _G.vim or {}
    _G.vim.lsp = _G.vim.lsp or {} -- Ensure vim.lsp exists for the check
    _G.vim.diagnostic = _G.vim.diagnostic or {}
    _G.vim.api = _G.vim.api or {}

    -- Default mocks
    _G.vim.diagnostic.get = spy.new(function()
      return {}
    end) -- Default to no diagnostics
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      return "/path/to/file_for_buf_" .. tostring(bufnr) .. ".lua"
    end)
  end)

  after_each(function()
    package.loaded["claudecode.tools.get_diagnostics"] = nil
    _G.vim.diagnostic.get = nil
    _G.vim.api.nvim_buf_get_name = nil
    -- Note: We don't nullify _G.vim.lsp or _G.vim.diagnostic entirely
    -- as they are checked for existence.
  end)

  it("should return an empty list if no diagnostics are found", function()
    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.diagnostics).to_be_table()
    expect(#result.diagnostics).to_be(0)
    assert.spy(_G.vim.diagnostic.get).was_called_with(0)
  end)

  it("should return formatted diagnostics if available", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 10, col = 5, severity = 1, message = "Error message 1", source = "linter1" },
      { bufnr = 2, lnum = 20, col = 15, severity = 2, message = "Warning message 2", source = "linter2" },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    expect(result.diagnostics).to_be_table()
    expect(#result.diagnostics).to_be(2)

    expect(result.diagnostics[1].file).to_be("/path/to/file_for_buf_1.lua")
    expect(result.diagnostics[1].line).to_be(10)
    expect(result.diagnostics[1].character).to_be(5)
    expect(result.diagnostics[1].severity).to_be(1)
    expect(result.diagnostics[1].message).to_be("Error message 1")
    expect(result.diagnostics[1].source).to_be("linter1")

    expect(result.diagnostics[2].file).to_be("/path/to/file_for_buf_2.lua")
    expect(result.diagnostics[2].severity).to_be(2)
    expect(result.diagnostics[2].message).to_be("Warning message 2")

    assert.spy(_G.vim.api.nvim_buf_get_name).was_called_with(1)
    assert.spy(_G.vim.api.nvim_buf_get_name).was_called_with(2)
  end)

  it("should filter out diagnostics with no file path", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 10, col = 5, severity = 1, message = "Error message 1", source = "linter1" },
      { bufnr = 99, lnum = 20, col = 15, severity = 2, message = "Warning message 2", source = "linter2" }, -- This one will have no path
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      if bufnr == 1 then
        return "/path/to/file1.lua"
      end
      if bufnr == 99 then
        return ""
      end -- No path for bufnr 99
      return "other.lua"
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    expect(#result.diagnostics).to_be(1)
    expect(result.diagnostics[1].file).to_be("/path/to/file1.lua")
  end)

  it("should error if vim.diagnostic.get is not available", function()
    _G.vim.diagnostic.get = nil
    local success, err = pcall(get_diagnostics_handler, {})
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Feature unavailable")
    assert_contains(err.data, "LSP or vim.diagnostic.get not available")
  end)

  it("should error if vim.diagnostic is not available", function()
    local old_diagnostic = _G.vim.diagnostic
    _G.vim.diagnostic = nil
    local success, err = pcall(get_diagnostics_handler, {})
    _G.vim.diagnostic = old_diagnostic -- Restore

    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
  end)

  it("should error if vim.lsp is not available for the check (though diagnostic is primary)", function()
    local old_lsp = _G.vim.lsp
    _G.vim.lsp = nil
    local success, err = pcall(get_diagnostics_handler, {})
    _G.vim.lsp = old_lsp -- Restore

    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
  end)
end)
