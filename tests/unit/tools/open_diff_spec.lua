require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: open_diff", function()
  local open_diff_handler
  local mock_diff_module

  before_each(function()
    -- Mock the diff module
    mock_diff_module = {
      open_diff = spy.new(function(old_path, new_path, new_contents, tab_name)
        -- Default success behavior
        return {
          provider = "mock_provider",
          tab_name = tab_name,
          success = true,
          error = nil,
        }
      end),
    }
    package.loaded["claudecode.diff"] = mock_diff_module

    -- Reset and require the module under test
    package.loaded["claudecode.tools.open_diff"] = nil
    open_diff_handler = require("claudecode.tools.open_diff").handler
  end)

  after_each(function()
    package.loaded["claudecode.diff"] = nil
    package.loaded["claudecode.tools.open_diff"] = nil
  end)

  local valid_params = {
    old_file_path = "old/file.txt",
    new_file_path = "new/file.txt",
    new_file_contents = "new content",
    tab_name = "MyDiff",
  }

  it("should error if old_file_path is missing", function()
    local params = vim.deepcopy(valid_params)
    params.old_file_path = nil
    local s, e = pcall(open_diff_handler, params)
    expect(s).to_be_false()
    expect(e.code).to_be(-32602)
    assert_contains(e.data, "Missing required parameter: old_file_path")
  end)

  it("should error if new_file_path is missing", function()
    local params = vim.deepcopy(valid_params)
    params.new_file_path = nil
    local s, e = pcall(open_diff_handler, params)
    expect(s).to_be_false()
    expect(e.code).to_be(-32602)
    assert_contains(e.data, "Missing required parameter: new_file_path")
  end)

  it("should error if new_file_contents is missing", function()
    local params = vim.deepcopy(valid_params)
    params.new_file_contents = nil
    local s, e = pcall(open_diff_handler, params)
    expect(s).to_be_false()
    expect(e.code).to_be(-32602)
    assert_contains(e.data, "Missing required parameter: new_file_contents")
  end)

  it("should error if tab_name is missing", function()
    local params = vim.deepcopy(valid_params)
    params.tab_name = nil
    local s, e = pcall(open_diff_handler, params)
    expect(s).to_be_false()
    expect(e.code).to_be(-32602)
    assert_contains(e.data, "Missing required parameter: tab_name")
  end)

  it("should call claudecode.diff.open_diff and return success message", function()
    local success, result = pcall(open_diff_handler, valid_params)
    expect(success).to_be_true()
    assert
      .spy(mock_diff_module.open_diff)
      .was_called_with(valid_params.old_file_path, valid_params.new_file_path, valid_params.new_file_contents, valid_params.tab_name)
    assert_contains(result.message, "Diff opened using mock_provider provider: MyDiff")
    expect(result.provider).to_be("mock_provider")
    expect(result.tab_name).to_be("MyDiff")
  end)

  it("should return error if diff_module.open_diff returns success=false", function()
    mock_diff_module.open_diff = spy.new(function()
      return { success = false, error = "Diff provider internal error" }
    end)
    local success, err = pcall(open_diff_handler, valid_params)
    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Error from diff provider")
    assert_contains(err.data, "Diff provider internal error")
  end)

  it("should return error if diff_module.open_diff itself errors (pcall fails)", function()
    mock_diff_module.open_diff = spy.new(function()
      error("Simulated error in diff_module.open_diff")
    end)
    local success, err = pcall(open_diff_handler, valid_params)
    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Error opening diff")
    assert_contains(err.data, "Simulated error in diff_module.open_diff")
  end)

  it("should handle pcall failure when requiring diff module", function()
    package.loaded["claudecode.diff"] = nil -- Ensure it's not cached
    local original_require = _G.require
    _G.require = function(mod_name)
      if mod_name == "claudecode.diff" then
        error("Simulated require failure for claudecode.diff")
      end
      return original_require(mod_name)
    end

    local success, err = pcall(open_diff_handler, valid_params)
    _G.require = original_require -- Restore original require

    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Internal server error")
    assert_contains(err.data, "Failed to load diff module")
  end)
end)
