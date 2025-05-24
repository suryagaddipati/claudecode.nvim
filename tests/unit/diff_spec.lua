-- luacheck: globals expect
require("tests.busted_setup")

describe("Diff Module", function()
  local diff
  local mock_vim

  local function setup()
    -- Clear module cache
    package.loaded["claudecode.diff"] = nil
    package.loaded["claudecode.config"] = nil

    -- Mock vim API
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
      },
      defer_fn = function(fn)
        fn()
      end,
      notify = function() end,
      log = { levels = { INFO = 2 } },
      deepcopy = function(t)
        local function copy(obj)
          if type(obj) ~= "table" then
            return obj
          end
          local result = {}
          for k, v in pairs(obj) do
            result[k] = copy(v)
          end
          return result
        end
        return copy(t)
      end,
      tbl_deep_extend = function(behavior, t1, t2)
        local function deep_extend(dest, src)
          for k, v in pairs(src) do
            if type(v) == "table" and type(dest[k]) == "table" then
              deep_extend(dest[k], v)
            else
              dest[k] = v
            end
          end
        end

        local result = {}
        for k, v in pairs(t1) do
          if type(v) == "table" then
            result[k] = {}
            for k2, v2 in pairs(v) do
              result[k][k2] = v2
            end
          else
            result[k] = v
          end
        end

        deep_extend(result, t2)
        return result
      end,
    }

    -- Replace vim with mock
    _G.vim = mock_vim

    diff = require("claudecode.diff")
  end

  local function teardown()
    _G.vim = nil
  end

  before_each(function()
    setup()
  end)

  after_each(function()
    teardown()
  end)

  describe("Provider Detection", function()
    it("should detect when diffview.nvim is not available", function()
      -- Mock require to fail for diffview
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local available = diff.is_diffview_available()
      expect(available).to_be_false()

      _G.require = old_require
    end)

    it("should detect when diffview.nvim is available", function()
      -- Mock require to succeed for diffview
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {} -- Mock diffview module
        end
        return old_require(name)
      end

      local available = diff.is_diffview_available()
      expect(available).to_be_true()

      _G.require = old_require
    end)
  end)

  describe("Provider Selection", function()
    it("should return native when diffview is not available and provider is auto", function()
      diff.setup({ diff_provider = "auto" })

      -- Mock diffview as unavailable
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")

      _G.require = old_require
    end)

    it("should return diffview when available and provider is auto", function()
      diff.setup({ diff_provider = "auto" })

      -- Mock diffview as available
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {} -- Mock diffview module
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("diffview")

      _G.require = old_require
    end)

    it("should return native when provider is explicitly set to native", function()
      diff.setup({ diff_provider = "native" })

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")
    end)

    it("should fallback to native when diffview provider is set but not available", function()
      diff.setup({ diff_provider = "diffview" })

      -- Mock diffview as unavailable
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")

      _G.require = old_require
    end)
  end)

  describe("Temporary File Management", function()
    it("should create temporary files with correct content", function()
      local test_content = "This is test content\nLine 2\nLine 3"
      local test_filename = "test.lua"

      -- Mock io.open
      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local tmp_file, err = diff._create_temp_file(test_content, test_filename)

      expect(tmp_file).to_be_string()
      expect(err).to_be_nil()

      -- Check string contains
      local tmp_file_str = tostring(tmp_file)
      expect(tmp_file_str:find("claudecode_diff", 1, true)).not_to_be_nil()
      expect(tmp_file_str:find(test_filename, 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)

    it("should handle file creation errors", function()
      local test_content = "test"
      local test_filename = "test.lua"

      -- Mock io.open to fail
      local old_io_open = io.open
      rawset(io, "open", function()
        return nil
      end)

      local tmp_file, err = diff._create_temp_file(test_content, test_filename)

      expect(tmp_file).to_be_nil()
      expect(err).to_be_string()
      expect(err:find("Failed to create temporary file", 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)
  end)

  describe("Native Diff Implementation", function()
    it("should create diff with correct parameters", function()
      diff.setup({
        diff_provider = "native",
        diff_opts = {
          vertical_split = true,
          show_diff_stats = false,
          auto_close_on_accept = true,
        },
      })

      -- Track vim commands
      local commands = {}
      mock_vim.cmd = function(cmd)
        table.insert(commands, cmd)
      end

      -- Mock io.open
      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_true()
      expect(result.provider).to_be("native")
      expect(result.tab_name).to_be("Test Diff")

      -- Verify commands were called
      local found_tabnew = false
      local found_diffthis = false
      local found_vertical_split = false

      for _, cmd in ipairs(commands) do
        if cmd:find("tabnew", 1, true) then
          found_tabnew = true
        end
        if cmd:find("diffthis", 1, true) then
          found_diffthis = true
        end
        if cmd:find("vertical split", 1, true) then
          found_vertical_split = true
        end
      end

      expect(found_tabnew).to_be_true()
      expect(found_diffthis).to_be_true()
      expect(found_vertical_split).to_be_true()

      rawset(io, "open", old_io_open)
    end)

    it("should use horizontal split when configured", function()
      diff.setup({
        diff_provider = "native",
        diff_opts = {
          vertical_split = false,
          show_diff_stats = false,
          auto_close_on_accept = true,
        },
      })

      -- Track vim commands
      local commands = {}
      mock_vim.cmd = function(cmd)
        table.insert(commands, cmd)
      end

      -- Mock io.open
      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_true()
      local found_split = false
      local found_vertical_split = false

      for _, cmd in ipairs(commands) do
        if cmd:find("split", 1, true) and not cmd:find("vertical split", 1, true) then
          found_split = true
        end
        if cmd:find("vertical split", 1, true) then
          found_vertical_split = true
        end
      end

      expect(found_split).to_be_true()
      expect(found_vertical_split).to_be_false()

      rawset(io, "open", old_io_open)
    end)

    it("should handle temporary file creation errors", function()
      diff.setup({ diff_provider = "native" })

      -- Mock io.open to fail
      local old_io_open = io.open
      rawset(io, "open", function()
        return nil
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_false()
      expect(result.error).to_be_string()
      expect(result.error:find("Failed to create temporary file", 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)
  end)

  describe("Open Diff Function", function()
    it("should use native provider when configured", function()
      diff.setup({ diff_provider = "native" })

      -- Mock the native diff function
      local native_called = false
      diff._open_native_diff = function(old_path, new_path, content, tab_name)
        native_called = true
        return {
          success = true,
          provider = "native",
          tab_name = tab_name,
        }
      end

      local result = diff.open_diff("/path/to/old.lua", "/path/to/new.lua", "new content", "Test Diff")

      expect(native_called).to_be_true()
      expect(result.provider).to_be("native")
      expect(result.success).to_be_true()
    end)

    it("should use diffview provider when available and configured", function()
      diff.setup({ diff_provider = "diffview" })

      -- Mock diffview as available
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {} -- Mock diffview module
        end
        return old_require(name)
      end

      -- Mock the diffview diff function
      local diffview_called = false
      diff._open_diffview_diff = function(old_path, new_path, content, tab_name)
        diffview_called = true
        return {
          success = true,
          provider = "diffview",
          tab_name = tab_name,
        }
      end

      local result = diff.open_diff("/path/to/old.lua", "/path/to/new.lua", "new content", "Test Diff")

      expect(diffview_called).to_be_true()
      expect(result.provider).to_be("diffview")

      _G.require = old_require
    end)
  end)

  teardown()
end)
