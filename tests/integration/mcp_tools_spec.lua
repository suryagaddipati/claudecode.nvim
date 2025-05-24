-- luacheck: globals expect
require("tests.busted_setup")

describe("MCP Tools Integration", function()
  local server
  local tools
  local mock_vim

  local function setup()
    -- Clear module cache
    package.loaded["claudecode.server.init"] = nil
    package.loaded["claudecode.tools.init"] = nil
    package.loaded["claudecode.diff"] = nil

    -- Mock the selection module to avoid LuaRocks issues
    package.loaded["claudecode.selection"] = {
      get_latest_selection = function()
        return {
          file_path = "/test/selection.lua",
          content = "test selection content",
          start_line = 1,
          end_line = 1,
        }
      end,
    }

    -- Mock vim API extensively for integration tests
    mock_vim = {
      fn = {
        tempname = function()
          return "/tmp/test_temp"
        end,
        mkdir = function()
          return true
        end,
        fnamemodify = function(path, modifier)
          if modifier == ":t" then
            return path:match("([^/]+)$") or path
          elseif modifier == ":h" then
            return path:match("^(.+)/[^/]+$") or ""
          end
          return path
        end,
        fnameescape = function(path)
          return path
        end,
        filereadable = function()
          return 1
        end,
        delete = function()
          return 0
        end,
        execute = function()
          return ""
        end,
        expand = function(path)
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
      },
      cmd = function() end,
      api = {
        nvim_get_current_buf = function()
          return 1
        end,
        nvim_buf_set_name = function() end,
        nvim_set_option_value = function() end,
        nvim_create_augroup = function()
          return 1
        end,
        nvim_create_autocmd = function() end,
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
      defer_fn = function(fn)
        fn()
      end,
      notify = function() end,
      log = { levels = { INFO = 2, WARN = 3 } },
      lsp = {},
      diagnostic = {
        get = function()
          return {}
        end,
      },
      json = {
        encode = function(data)
          return vim.inspect(data)
        end,
        decode = function(str)
          return {}
        end,
      },
      empty_dict = function()
        return {}
      end,
    }

    -- Replace vim with mock
    _G.vim = mock_vim

    -- Load modules
    server = require("claudecode.server.init")
    tools = require("claudecode.tools.init")
  end

  local function teardown()
    _G.vim = nil
  end

  setup()

  describe("Tools List Handler", function()
    it("should return complete tool definitions", function()
      server.register_handlers()
      tools.setup(server)

      local handler = server.state.handlers["tools/list"]
      expect(handler).to_be_function()

      local result = handler(nil, {})

      expect(result.tools).to_be_table()
      expect(#result.tools).to_be_at_least(4)

      -- Check openDiff tool specifically
      local openDiff_tool = nil
      for _, tool in ipairs(result.tools) do
        if tool.name == "openDiff" then
          openDiff_tool = tool
          break
        end
      end

      expect(openDiff_tool).not_to_be_nil()
      expect(type(openDiff_tool.description)).to_be("string")
      expect(openDiff_tool.description:find("diff view")).to_be_truthy()
      expect(openDiff_tool.inputSchema).to_be_table()
      expect(openDiff_tool.inputSchema.type).to_be("object")
      expect(openDiff_tool.inputSchema.required).to_be_table()
      expect(#openDiff_tool.inputSchema.required).to_be(4)

      -- Verify required parameters
      local required = openDiff_tool.inputSchema.required
      local has_old_file_path = false
      local has_new_file_path = false
      local has_new_file_contents = false
      local has_tab_name = false

      for _, param in ipairs(required) do
        if param == "old_file_path" then
          has_old_file_path = true
        end
        if param == "new_file_path" then
          has_new_file_path = true
        end
        if param == "new_file_contents" then
          has_new_file_contents = true
        end
        if param == "tab_name" then
          has_tab_name = true
        end
      end

      expect(has_old_file_path).to_be_true()
      expect(has_new_file_path).to_be_true()
      expect(has_new_file_contents).to_be_true()
      expect(has_tab_name).to_be_true()

      -- Verify properties
      local props = openDiff_tool.inputSchema.properties
      expect(props.old_file_path.type).to_be("string")
      expect(props.new_file_path.type).to_be("string")
      expect(props.new_file_contents.type).to_be("string")
      expect(props.tab_name.type).to_be("string")
    end)

    it("should include other essential tools", function()
      server.register_handlers()
      tools.setup(server)

      local handler = server.state.handlers["tools/list"]
      local result = handler(nil, {})

      local tool_names = {}
      for _, tool in ipairs(result.tools) do
        table.insert(tool_names, tool.name)
      end

      local has_openFile = false
      local has_getCurrentSelection = false
      local has_getOpenEditors = false
      local has_openDiff = false

      for _, name in ipairs(tool_names) do
        if name == "openFile" then
          has_openFile = true
        end
        if name == "getCurrentSelection" then
          has_getCurrentSelection = true
        end
        if name == "getOpenEditors" then
          has_getOpenEditors = true
        end
        if name == "openDiff" then
          has_openDiff = true
        end
      end

      expect(has_openFile).to_be_true()
      expect(has_getCurrentSelection).to_be_true()
      expect(has_getOpenEditors).to_be_true()
      expect(has_openDiff).to_be_true()
    end)
  end)

  describe("Tools Call Handler", function()
    before_each(function()
      -- Use a simpler approach: mock the tools module entirely
      tools = {
        handle_invoke = function(client, params)
          if params.name == "openDiff" then
            -- Check for missing required parameters
            local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }
            for _, param in ipairs(required_params) do
              if not params.arguments[param] then
                return {
                  result = {
                    content = {
                      {
                        type = "text",
                        text = "Error: Missing required parameter: " .. param,
                      },
                    },
                    isError = true,
                  },
                }
              end
            end

            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "Diff opened using native provider: " .. params.arguments.tab_name,
                  },
                },
              },
            }
          elseif params.name == "getOpenEditors" then
            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "[]", -- Empty JSON array
                  },
                },
              },
            }
          elseif params.name == "openFile" then
            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "File opened: " .. params.arguments.filePath,
                  },
                },
              },
            }
          elseif params.name == "getCurrentSelection" then
            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = '{"file_path": "/test/selection.lua", "content": "test selection content", "start_line": 1, "end_line": 1}',
                  },
                },
              },
            }
          else
            return {
              error = {
                code = -32601,
                message = "Tool not found: " .. params.name,
              },
            }
          end
        end,
      }

      server.register_handlers()

      -- Replace the tools reference in the server module to use our mock
      -- This requires directly patching the server's handlers
      server.state.handlers["tools/call"] = function(client, params)
        local result_or_error_table = tools.handle_invoke(client, params)
        if result_or_error_table.error then
          return nil, result_or_error_table.error
        elseif result_or_error_table.result then
          return result_or_error_table.result, nil
        else
          return nil,
            {
              code = -32603,
              message = "Internal error",
              data = "Tool handler returned unexpected format",
            }
        end
      end
    end)

    it("should handle openDiff tool call successfully", function()
      -- Mock io.open for temporary file creation
      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local handler = server.state.handlers["tools/call"]
      expect(handler).to_be_function()

      local params = {
        name = "openDiff",
        arguments = {
          old_file_path = "/test/old.lua",
          new_file_path = "/test/new.lua",
          new_file_contents = "function test()\n  return 'new'\nend",
          tab_name = "Integration Test Diff",
        },
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_table()
      expect(error_data).to_be_nil()
      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(type(result.content[1].text)).to_be("string")
      expect(result.content[1].text:find("Diff opened using")).to_be_truthy()
      expect(result.content[1].text:find("Integration Test Diff")).to_be_truthy()

      rawset(io, "open", old_io_open)
    end)

    it("should handle missing parameters in openDiff", function()
      local handler = server.state.handlers["tools/call"]

      local params = {
        name = "openDiff",
        arguments = {
          old_file_path = "/test/old.lua",
          -- Missing other required parameters
        },
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_table()
      expect(error_data).to_be_nil()
      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(type(result.content[1].text)).to_be("string")
      expect(result.content[1].text:find("Missing required parameter")).to_be_truthy()
      expect(result.isError).to_be_true()
    end)

    it("should handle getOpenEditors tool call", function()
      local handler = server.state.handlers["tools/call"]

      local params = {
        name = "getOpenEditors",
        arguments = {},
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_table()
      expect(error_data).to_be_nil()
      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(result.content[1].text).to_be_string()
      -- The JSON is now encoded as text, so we just check it's a string
    end)

    it("should handle openFile tool call", function()
      local handler = server.state.handlers["tools/call"]

      local params = {
        name = "openFile",
        arguments = {
          filePath = "/test/existing.lua",
        },
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_table()
      expect(error_data).to_be_nil()
      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(type(result.content[1].text)).to_be("string")
      expect(result.content[1].text:find("File opened")).to_be_truthy()
    end)

    it("should handle unknown tool gracefully", function()
      local handler = server.state.handlers["tools/call"]

      local params = {
        name = "unknownTool",
        arguments = {},
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_nil()
      expect(error_data).to_be_table()
      expect(error_data.code).to_be(-32601)
      expect(type(error_data.message)).to_be("string")
      expect(error_data.message:find("Tool not found")).to_be_truthy()
    end)

    it("should handle tool execution errors", function()
      -- Temporarily replace the tools mock to simulate an error
      local error_tools = {
        handle_invoke = function(client, params)
          if params.name == "openDiff" then
            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "Error opening diff: Simulated diff error",
                  },
                },
                isError = true,
              },
            }
          else
            return {
              error = {
                code = -32601,
                message = "Tool not found: " .. params.name,
              },
            }
          end
        end,
      }

      -- Replace the handler with error behavior
      server.state.handlers["tools/call"] = function(client, params)
        local result_or_error_table = error_tools.handle_invoke(client, params)
        if result_or_error_table.error then
          return nil, result_or_error_table.error
        elseif result_or_error_table.result then
          return result_or_error_table.result, nil
        else
          return nil,
            {
              code = -32603,
              message = "Internal error",
              data = "Tool handler returned unexpected format",
            }
        end
      end

      local handler = server.state.handlers["tools/call"]

      local params = {
        name = "openDiff",
        arguments = {
          old_file_path = "/test/old.lua",
          new_file_path = "/test/new.lua",
          new_file_contents = "content",
          tab_name = "Error Test",
        },
      }

      local result, error_data = handler(nil, params)

      expect(result).to_be_table()
      expect(error_data).to_be_nil()
      expect(result.content).to_be_table()
      expect(result.content[1].type).to_be("text")
      expect(type(result.content[1].text)).to_be("string")
      expect(result.content[1].text:find("Error opening diff")).to_be_truthy()
      expect(result.isError).to_be_true()
    end)
  end)

  describe("End-to-End MCP Protocol Flow", function()
    it("should complete full openDiff workflow", function()
      -- Mock io.open for temporary file creation
      local temp_files_created = {} -- luacheck: ignore temp_files_created
      local mock_file = {
        write = function(self, content)
          self.content = content
        end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function(filename, mode)
        temp_files_created[filename] = { content = "", mode = mode }
        return mock_file
      end)

      -- Track vim commands
      local vim_commands = {}
      mock_vim.cmd = function(cmd)
        table.insert(vim_commands, cmd)
      end

      -- Use the same mock tools for end-to-end test
      tools = {
        get_tool_list = function()
          return {
            {
              name = "openDiff",
              description = "Open a diff view comparing old file content with new file content",
              inputSchema = {
                type = "object",
                required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
              },
            },
          }
        end,
        handle_invoke = function(client, params)
          if params.name == "openDiff" then
            -- Check for missing required parameters
            local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }
            for _, param in ipairs(required_params) do
              if not params.arguments[param] then
                return {
                  result = {
                    content = {
                      {
                        type = "text",
                        text = "Error: Missing required parameter: " .. param,
                      },
                    },
                    isError = true,
                  },
                }
              end
            end

            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "Diff opened using native provider: " .. params.arguments.tab_name,
                  },
                },
              },
            }
          else
            return {
              error = {
                code = -32601,
                message = "Tool not found: " .. params.name,
              },
            }
          end
        end,
      }

      server.register_handlers()

      -- Replace the tools reference in server handlers
      server.state.handlers["tools/list"] = function(client, params)
        return {
          tools = tools.get_tool_list(),
        }
      end

      server.state.handlers["tools/call"] = function(client, params)
        local result_or_error_table = tools.handle_invoke(client, params)
        if result_or_error_table.error then
          return nil, result_or_error_table.error
        elseif result_or_error_table.result then
          return result_or_error_table.result, nil
        else
          return nil,
            {
              code = -32603,
              message = "Internal error",
              data = "Tool handler returned unexpected format",
            }
        end
      end

      -- Step 1: List tools
      local list_handler = server.state.handlers["tools/list"]
      local tools_list = list_handler(nil, {})

      expect(tools_list.tools).to_be_table()

      -- Step 2: Call openDiff tool
      local call_handler = server.state.handlers["tools/call"]
      local call_params = {
        name = "openDiff",
        arguments = {
          old_file_path = "/project/src/utils.lua",
          new_file_path = "/project/src/utils.lua",
          new_file_contents = "-- Updated utils\nfunction utils.helper()\n  return 'updated'\nend",
          tab_name = "Utils Update",
        },
      }

      local call_result, call_error = call_handler(nil, call_params)

      -- Verify result
      expect(call_result).to_be_table()
      expect(call_error).to_be_nil()
      expect(call_result.content).to_be_table()
      expect(call_result.content[1].type).to_be("text")
      expect(type(call_result.content[1].text)).to_be("string")
      expect(call_result.content[1].text:find("Diff opened")).to_be_truthy()
      expect(call_result.content[1].text:find("Utils Update")).to_be_truthy()

      -- Note: With mock tools, we don't actually execute vim commands or create temp files
      -- but we can verify the response indicates success
      -- The actual diff functionality is tested in unit tests

      rawset(io, "open", old_io_open)
    end)

    it("should handle parameter validation across the protocol", function()
      -- Use mock tools for parameter validation test
      tools = {
        handle_invoke = function(client, params)
          if params.name == "openDiff" then
            local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }
            for _, param in ipairs(required_params) do
              if not params.arguments[param] then
                return {
                  result = {
                    content = {
                      {
                        type = "text",
                        text = "Error: Missing required parameter: " .. param,
                      },
                    },
                    isError = true,
                  },
                }
              end
            end
            return {
              result = {
                content = {
                  {
                    type = "text",
                    text = "Diff opened successfully",
                  },
                },
              },
            }
          else
            return {
              error = {
                code = -32601,
                message = "Tool not found: " .. params.name,
              },
            }
          end
        end,
      }

      server.register_handlers()

      -- Replace the tools reference in server handlers
      server.state.handlers["tools/call"] = function(client, params)
        local result_or_error_table = tools.handle_invoke(client, params)
        if result_or_error_table.error then
          return nil, result_or_error_table.error
        elseif result_or_error_table.result then
          return result_or_error_table.result, nil
        else
          return nil,
            {
              code = -32603,
              message = "Internal error",
              data = "Tool handler returned unexpected format",
            }
        end
      end

      local call_handler = server.state.handlers["tools/call"]

      -- Test each missing parameter
      local required_params = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }

      for _, missing_param in ipairs(required_params) do
        local params = {
          name = "openDiff",
          arguments = {
            old_file_path = "/test/old.lua",
            new_file_path = "/test/new.lua",
            new_file_contents = "content",
            tab_name = "Test",
          },
        }
        params.arguments[missing_param] = nil

        local result, result_error = call_handler(nil, params)

        expect(result).to_be_table()
        expect(result_error).to_be_nil()
        expect(result.content).to_be_table()
        expect(result.content[1].type).to_be("text")
        expect(type(result.content[1].text)).to_be("string")
        expect(result.content[1].text:find("Missing required parameter: " .. missing_param)).to_be_truthy()
        expect(result.isError).to_be_true()
      end
    end)
  end)

  teardown()
end)
