-- Tests for lockfile module

-- Load mock vim if needed
local real_vim = _G.vim
if not _G.vim then
  -- Create a basic vim mock
  _G.vim = { ---@type vim_global_api
    schedule_wrap = function(fn)
      return fn
    end,
    deepcopy = function(t) -- Basic deepcopy for testing
      local copy = {}
      for k, v in pairs(t) do
        if type(v) == "table" then
          copy[k] = _G.vim.deepcopy(v)
        else
          copy[k] = v
        end
      end
      return copy
    end,
    cmd = function() end, ---@type fun(command: string):nil
    api = {}, ---@type table
    fs = { remove = function() end }, ---@type vim_fs_module
    fn = { ---@type vim_fn_table
      expand = function(path)
        return select(1, path:gsub("~", "/home/user"))
      end,
      -- Add other vim.fn mocks as needed by lockfile tests
      -- For now, only adding what's explicitly used or causing major type issues
      filereadable = function()
        return 1
      end,
      fnamemodify = function(fname, _)
        return fname
      end,
      delete = function(_, _)
        return 0
      end,
      mode = function()
        return "n"
      end,
      buflisted = function(_)
        return 0
      end,
      bufname = function(_)
        return ""
      end,
      bufnr = function(_)
        return 0
      end,
      win_getid = function()
        return 0
      end,
      win_gotoid = function(_)
        return false
      end,
      line = function(_)
        return 0
      end,
      col = function(_)
        return 0
      end,
      virtcol = function(_)
        return 0
      end,
      getpos = function(_)
        return { 0, 0, 0, 0 }
      end,
      setpos = function(_, _)
        return false
      end,
      tempname = function()
        return ""
      end,
      globpath = function(_, _)
        return ""
      end,
      stdpath = function(_)
        return ""
      end,
      json_encode = function(_)
        return "{}"
      end,
      json_decode = function(_)
        return {}
      end,
      -- getcwd is defined later in setup, so no need to mock it here initially
      -- mkdir is defined later in setup
      -- getpid is defined later in setup
      getcwd = function()
        return "/mock/cwd"
      end,
      mkdir = function()
        return 1
      end,
      getpid = function()
        return 12345
      end,
      termopen = function(_, _)
        return 0
      end,
    },
    notify = function(_, _, _) end,
    log = {
      levels = {
        NONE = 0,
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        DEBUG = 4,
        TRACE = 5,
      },
    },
    json = {
      encode = function(_obj) -- Prefix unused param with underscore
        return '{"mocked":"json"}'
      end,
    },
    lsp = {}, -- Existing lsp mock part
    o = { ---@type vim_options_table
      columns = 80,
      lines = 24,
    },
    bo = setmetatable({}, { -- Mock for vim.bo and vim.bo[bufnr]
      __index = function(t, k)
        if type(k) == "number" then
          -- vim.bo[bufnr] accessed, return a new proxy table for this buffer
          if not t[k] then
            t[k] = {} ---@type vim_buffer_options_table
          end
          return t[k]
        end
        -- vim.bo.option_name (global buffer option)
        return nil -- Return nil or a default mock value if needed
      end, -- REMOVED COMMA from here (was after 'end')
      -- __newindex can be added here if setting options is needed for tests
      -- e.g., __newindex = function(t, k, v) rawset(t, k, v) end,
    }), ---@type vim_bo_proxy
    diagnostic = { ---@type vim_diagnostic_module
      get = function()
        return {}
      end,
      -- Add other vim.diagnostic functions as needed for tests
    },
    empty_dict = function()
      return {}
    end,
  } -- This is the closing brace for _G.vim table
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
      assert("/mock/cwd" == folders[1])
    end)

    it("should work with current Neovim API (get_clients)", function()
      -- Set up the current API mock
      create_mock_env("current")

      -- Test the function
      local folders = lockfile.get_workspace_folders()

      -- Verify results
      assert(3 == #folders) -- cwd + 2 workspace folders
      assert("/mock/folder1" == folders[2])
      assert("/mock/folder2" == folders[3])
    end)

    it("should work with legacy Neovim API (get_active_clients)", function()
      -- Set up the legacy API mock
      create_mock_env("legacy")

      -- Test the function
      local folders = lockfile.get_workspace_folders()

      -- Verify results
      assert(3 == #folders) -- cwd + 2 workspace folders
      assert("/mock/folder1" == folders[2])
      assert("/mock/folder2" == folders[3])
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
      assert(2 == #folders) -- cwd + 1 unique workspace folder
    end)
  end)
end)
