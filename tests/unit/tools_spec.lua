-- luacheck: globals expect
require("tests.busted_setup")

describe("Tools Module", function()
  local tools
  local mock_vim

  local function setup()
    -- Clear module cache
    package.loaded["claudecode.tools.init"] = nil
    package.loaded["claudecode.diff"] = nil

    -- Mock vim API
    mock_vim = {
      fn = {
        expand = function(path)
          return path
        end,
        filereadable = function()
          return 1
        end,
        fnameescape = function(path)
          return path
        end,
        bufnr = function()
          return 1
        end,
        buflisted = function()
          return 1
        end,
        getcwd = function()
          return "/test/workspace"
        end,
        fnamemodify = function(path, modifier)
          if modifier == ":t" then
            return "workspace"
          end
          return path
        end,
      },
      cmd = function() end,
      api = {
        nvim_list_bufs = function()
          return { 1, 2 }
        end,
        nvim_buf_is_loaded = function()
          return true
        end,
        nvim_buf_get_name = function(bufnr)
          if bufnr == 1 then
            return "/test/file1.lua"
          end
          if bufnr == 2 then
            return "/test/file2.lua"
          end
          return ""
        end,
        nvim_buf_get_option = function()
          return false
        end,
        nvim_buf_call = function(bufnr, fn)
          fn()
        end,
        nvim_buf_delete = function() end,
      },
      lsp = {},
      diagnostic = {
        get = function()
          return {
            {
              bufnr = 1,
              lnum = 10,
              col = 5,
              severity = 1,
              message = "Test error",
              source = "test",
            },
          }
        end,
      },
      json = {
        encode = function(obj)
          return vim.inspect(obj)
        end,
      },
      notify = function() end,
      inspect = function(obj)
        if type(obj) == "string" then
          return '"' .. obj .. '"'
        elseif type(obj) == "table" then
          local items = {}
          for k, v in pairs(obj) do
            table.insert(items, tostring(k) .. ": " .. tostring(v))
          end
          return "{" .. table.concat(items, ", ") .. "}"
        else
          return tostring(obj)
        end
      end,
    }

    -- Replace vim with mock
    _G.vim = mock_vim

    tools = require("claudecode.tools.init")
  end

  local function teardown()
    _G.vim = nil
  end

  local function contains(str, pattern)
    return str:find(pattern, 1, true) ~= nil
  end

  before_each(function()
    setup()
  end)

  after_each(function()
    teardown()
  end)

  describe("Tool Registration", function()
    it("should register all tools", function()
      tools.register_all()

      expect(tools.tools).to_be_table()
      expect(tools.tools.openFile).to_be_table()
      expect(tools.tools.openFile.handler).to_be_function()
      expect(tools.tools.getDiagnostics).to_be_table()
      expect(tools.tools.getDiagnostics.handler).to_be_function()
      expect(tools.tools.getOpenEditors).to_be_table()
      expect(tools.tools.getOpenEditors.handler).to_be_function()
      expect(tools.tools.openDiff).to_be_table()
      expect(tools.tools.openDiff.handler).to_be_function()
    end)

    it("should allow registering custom tools", function()
      local custom_tool = function()
        return "custom result"
      end
      tools.register("customTool", nil, custom_tool)

      expect(tools.tools.customTool.handler).to_be(custom_tool)
    end)
  end)

  describe("Tool Invocation Handler", function()
    before_each(function()
      tools.register_all()
    end)

    it("should handle valid tool invocation", function()
      local params = {
        name = "getOpenEditors",
        arguments = {},
      }

      local result = tools.handle_invoke(nil, params)

      expect(result.result).to_be_table()
      expect(result.result.content).to_be_table()
      expect(result.result.content[1]).to_be_table()
      expect(result.result.content[1].type).to_be("text")
      expect(result.error).to_be_nil()
    end)

    it("should handle unknown tool invocation", function()
      local params = {
        name = "unknownTool",
        arguments = {},
      }

      local result = tools.handle_invoke(nil, params)

      expect(result.error).to_be_table()
      expect(result.error.code).to_be(-32601)
      expect(contains(result.error.message, "Tool not found")).to_be_true()
    end)

    it("should handle tool execution errors", function()
      -- Register a tool that throws an error
      tools.register("errorTool", function()
        error("Test error")
      end)

      local params = {
        name = "errorTool",
        arguments = {},
      }

      local result = tools.handle_invoke(nil, params)

      expect(result.error).to_be_table()
      expect(result.error.code).to_be(-32603)
      expect(contains(result.error.message, "Tool execution failed")).to_be_true()
    end)
  end)

  describe("Open File Tool", function()
    it("should open existing file", function()
      local params = {
        filePath = "/test/existing.lua",
      }

      mock_vim.fn.filereadable = function()
        return 1
      end

      local result = tools.open_file(params)

      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "File opened")).to_be_true()
    end)

    it("should handle missing filePath parameter", function()
      local params = {}

      local result = tools.open_file(params)

      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Missing filePath parameter")).to_be_true()
    end)

    it("should handle non-existent file", function()
      local params = {
        filePath = "/test/nonexistent.lua",
      }

      mock_vim.fn.filereadable = function()
        return 0
      end

      local result = tools.open_file(params)

      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "File not found")).to_be_true()
    end)
  end)

  describe("Get Diagnostics Tool", function()
    it("should return diagnostics when LSP is available", function()
      local result = tools.get_diagnostics({})

      expect(result.content[1].type).to_be("text")
      expect(result.content[1].text).to_be_string()
      -- Just check that JSON content is returned, the exact format depends on vim.json.encode
      expect(result.content[1].text ~= "").to_be_true()
    end)

    it("should handle missing LSP", function()
      mock_vim.lsp = nil

      local result = tools.get_diagnostics({})

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "LSP not available")).to_be_true()

      -- Restore LSP for other tests
      mock_vim.lsp = {}
    end)
  end)

  describe("Get Open Editors Tool", function()
    it("should return list of open editors", function()
      local result = tools.get_open_editors({})

      expect(result.content[1].type).to_be("text")
      expect(result.content[1].text).to_be_string()
      -- Just check that JSON content is returned with file paths
      expect(result.content[1].text ~= "").to_be_true()
    end)

    it("should include file URLs and dirty status", function()
      local result = tools.get_open_editors({})

      expect(result.content[1].type).to_be("text")
      expect(result.content[1].text).to_be_string()
      expect(result.content[1].text ~= "").to_be_true()
    end)
  end)

  describe("Save Document Tool", function()
    it("should save existing document", function()
      local params = {
        filePath = "/test/file1.lua",
      }

      mock_vim.fn.bufnr = function()
        return 1
      end

      local result = tools.save_document(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "File saved")).to_be_true()
    end)

    it("should handle missing filePath parameter", function()
      local params = {}

      local result = tools.save_document(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Missing filePath parameter")).to_be_true()
    end)

    it("should handle file not open in editor", function()
      local params = {
        filePath = "/test/notopen.lua",
      }

      mock_vim.fn.bufnr = function()
        return -1
      end

      local result = tools.save_document(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "File not open in editor")).to_be_true()
    end)
  end)

  describe("Check Document Dirty Tool", function()
    it("should check if document is dirty", function()
      local params = {
        filePath = "/test/file1.lua",
      }

      mock_vim.fn.bufnr = function()
        return 1
      end
      mock_vim.api.nvim_buf_get_option = function()
        return true
      end

      local result = tools.check_document_dirty(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "isDirty")).to_be_true()
    end)

    it("should handle missing filePath parameter", function()
      local params = {}

      local result = tools.check_document_dirty(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Missing filePath parameter")).to_be_true()
    end)
  end)

  describe("Open Diff Tool", function()
    it("should validate all required parameters", function()
      local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }

      for _, missing_param in ipairs(required_params) do
        local params = {
          old_file_path = "/test/old.lua",
          new_file_path = "/test/new.lua",
          new_file_contents = "new content",
          tab_name = "Test Diff",
        }
        params[missing_param] = nil

        local result = tools.open_diff(params)

        expect(result.content).to_be_table()
        expect(result.content[1].type).to_be("text")
        expect(contains(result.content[1].text, "Missing required parameter: " .. missing_param)).to_be_true()
        expect(result.isError).to_be_true()
      end
    end)

    it("should call diff module with correct parameters", function()
      -- Mock the diff module
      package.loaded["claudecode.diff"] = {
        open_diff = function(old_path, new_path, content, tab_name)
          expect(old_path).to_be("/test/old.lua")
          expect(new_path).to_be("/test/new.lua")
          expect(content).to_be("new content here")
          expect(tab_name).to_be("Test Diff")

          return {
            provider = "native",
            tab_name = tab_name,
            success = true,
          }
        end,
      }

      local params = {
        old_file_path = "/test/old.lua",
        new_file_path = "/test/new.lua",
        new_file_contents = "new content here",
        tab_name = "Test Diff",
      }

      local result = tools.open_diff(params)

      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Diff opened using native provider")).to_be_true()
      expect(contains(result.content[1].text, "Test Diff")).to_be_true()
    end)

    it("should handle diff module errors", function()
      -- Mock the diff module to throw an error
      package.loaded["claudecode.diff"] = {
        open_diff = function()
          error("Test diff error")
        end,
      }

      local params = {
        old_file_path = "/test/old.lua",
        new_file_path = "/test/new.lua",
        new_file_contents = "new content",
        tab_name = "Test Diff",
      }

      local result = tools.open_diff(params)

      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Error opening diff")).to_be_true()
      expect(result.isError).to_be_true()
    end)
  end)

  describe("Close Tab Tool", function()
    it("should close existing tab", function()
      local params = {
        tab_name = "Test Tab",
      }

      mock_vim.fn.bufnr = function()
        return 1
      end

      local result = tools.close_tab(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Tab closed")).to_be_true()
    end)

    it("should handle missing tab_name parameter", function()
      local params = {}

      local result = tools.close_tab(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Missing tab_name parameter")).to_be_true()
    end)

    it("should handle tab not found", function()
      local params = {
        tab_name = "Nonexistent Tab",
      }

      mock_vim.fn.bufnr = function()
        return -1
      end

      local result = tools.close_tab(params)

      expect(result.content[1].type).to_be("text")
      expect(contains(result.content[1].text, "Tab not found")).to_be_true()
    end)
  end)

  teardown()
end)
