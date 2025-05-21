-- Tests for lockfile module

-- Load mock vim if needed
local real_vim = _G.vim
if not _G.vim then
  -- Create a basic vim mock
  _G.vim = {
    fn = {
      expand = function(path)
        return path:gsub("~", "/home/user")
      end,
      getcwd = function()
        return "/mock/cwd"
      end,
      mkdir = function()
        return 1
      end,
      getpid = function()
        return 12345
      end,
      filereadable = function()
        return 1
      end,
    },
    json = {
      encode = function(_obj) -- Prefix unused param with underscore
        return '{"mocked":"json"}'
      end,
    },
    lsp = {},
  }
end

describe("Lockfile Module", function()
  local lockfile

  -- Save original vim functions/tables (not used in this test but kept for reference)
  -- luacheck: ignore
  local orig_vim = _G.vim
  local orig_fn_getcwd = vim.fn.getcwd
  local orig_lsp = vim.lsp
  -- luacheck: no ignore

  -- Create a mock for testing LSP client resolution
  local create_mock_env = function(api_version)
    -- Configure mock based on API version
    local mock_lsp = {}

    -- Test workspace folders data
    local test_workspace_data = {
      {
        config = {
          workspace_folders = {
            { uri = "file:///mock/folder1" },
            { uri = "file:///mock/folder2" },
          },
        },
      },
    }

    if api_version == "current" then
      -- Neovim 0.11+ API (get_clients)
      mock_lsp.get_clients = function()
        return test_workspace_data
      end
    elseif api_version == "legacy" then
      -- Neovim 0.8-0.10 API (get_active_clients)
      mock_lsp.get_active_clients = function()
        return test_workspace_data
      end
    end

    -- Apply mock
    vim.lsp = mock_lsp
  end

  setup(function()
    -- Mock required vim functions before loading the module
    vim.fn.getcwd = function()
      return "/mock/cwd"
    end

    -- Load the lockfile module for all tests
    package.loaded["claudecode.lockfile"] = nil -- Clear any previous requires
    lockfile = require("claudecode.lockfile")
  end)

  teardown(function()
    -- Restore original vim
    if real_vim then
      _G.vim = real_vim
    end
  end)

  describe("get_workspace_folders()", function()
    before_each(function()
      -- Ensure consistent path
      vim.fn.getcwd = function()
        return "/mock/cwd"
      end
    end)

    after_each(function()
      -- Restore lsp table to clean state
      vim.lsp = {}
    end)

    it("should include the current working directory", function()
      local folders = lockfile.get_workspace_folders()
      assert.equals("/mock/cwd", folders[1])
    end)

    it("should work with current Neovim API (get_clients)", function()
      -- Set up the current API mock
      create_mock_env("current")

      -- Test the function
      local folders = lockfile.get_workspace_folders()

      -- Verify results
      assert.equals(3, #folders) -- cwd + 2 workspace folders
      assert.equals("/mock/folder1", folders[2])
      assert.equals("/mock/folder2", folders[3])
    end)

    it("should work with legacy Neovim API (get_active_clients)", function()
      -- Set up the legacy API mock
      create_mock_env("legacy")

      -- Test the function
      local folders = lockfile.get_workspace_folders()

      -- Verify results
      assert.equals(3, #folders) -- cwd + 2 workspace folders
      assert.equals("/mock/folder1", folders[2])
      assert.equals("/mock/folder2", folders[3])
    end)

    it("should handle duplicate folder paths", function()
      -- Set up a mock with duplicates
      vim.lsp = {
        get_clients = function()
          return {
            {
              config = {
                workspace_folders = {
                  { uri = "file:///mock/cwd" }, -- Same as cwd
                  { uri = "file:///mock/folder" },
                  { uri = "file:///mock/folder" }, -- Duplicate
                },
              },
            },
          }
        end,
      }

      -- Test the function
      local folders = lockfile.get_workspace_folders()

      -- Verify results
      assert.equals(2, #folders) -- cwd + 1 unique workspace folder
    end)
  end)
end)
