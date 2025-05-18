-- Simple selection module tests

-- Create mock vim API
if not _G.vim then
  _G.vim = {
    -- Mock values
    _buffers = {},
    _windows = {},
    _commands = {},
    _autocmds = {},
    _vars = {},
    _options = {},
    _current_mode = "n",

    -- Mock API
    api = {
      -- Create user command
      nvim_create_user_command = function(name, callback, opts)
        _G.vim._commands[name] = {
          callback = callback,
          opts = opts,
        }
      end,

      -- Create autocommand group
      nvim_create_augroup = function(name, opts)
        _G.vim._autocmds[name] = {
          opts = opts,
          events = {},
        }
        return name
      end,

      -- Create autocommand
      nvim_create_autocmd = function(events, opts)
        local group = opts.group or "default"
        if not _G.vim._autocmds[group] then
          _G.vim._autocmds[group] = {
            opts = {},
            events = {},
          }
        end

        local id = #_G.vim._autocmds[group].events + 1
        _G.vim._autocmds[group].events[id] = {
          events = events,
          opts = opts,
        }

        return id
      end,

      -- Clear autocommands
      nvim_clear_autocmds = function(opts)
        if opts.group then
          _G.vim._autocmds[opts.group] = nil
        end
      end,

      -- Get current buffer
      nvim_get_current_buf = function()
        return 1
      end,

      -- Get buffer name
      nvim_buf_get_name = function(bufnr)
        return _G.vim._buffers[bufnr] and _G.vim._buffers[bufnr].name or ""
      end,

      -- Get current window
      nvim_get_current_win = function()
        return 1
      end,

      -- Get cursor position
      nvim_win_get_cursor = function(winid)
        return _G.vim._windows[winid] and _G.vim._windows[winid].cursor or { 1, 0 }
      end,

      -- Get mode
      nvim_get_mode = function()
        return { mode = _G.vim._current_mode }
      end,

      -- Get buffer lines
      nvim_buf_get_lines = function(bufnr, start, end_line, strict)
        if not _G.vim._buffers[bufnr] then
          return {}
        end

        local lines = _G.vim._buffers[bufnr].lines or {}
        local result = {}

        for i = start + 1, end_line do
          table.insert(result, lines[i] or "")
        end

        return result
      end,

      -- Echo message
      nvim_echo = function(chunks, history, opts)
        -- Just store the last echo message for testing
        _G.vim._last_echo = {
          chunks = chunks,
          history = history,
          opts = opts,
        }
      end,

      -- Error message
      nvim_err_writeln = function(msg)
        _G.vim._last_error = msg
      end,
    },

    -- Mock fn functions
    fn = {
      -- Get buffer number
      bufnr = function(name)
        for bufnr, buf in pairs(_G.vim._buffers) do
          if buf.name == name then
            return bufnr
          end
        end
        return -1
      end,

      -- Get visual selection start position
      getpos = function(mark)
        if mark == "'<" then
          return { 0, 1, 1, 0 }
        elseif mark == "'>" then
          return { 0, 5, 10, 0 }
        end
        return { 0, 0, 0, 0 }
      end,
    },

    -- Mock defer_fn
    defer_fn = function(fn, timeout)
      -- For testing, we'll execute immediately
      fn()
    end,

    -- Mock vim.loop
    loop = {
      -- Timer functions
      timer_stop = function(timer)
        return true
      end,
    },

    -- Test helpers
    test = {
      -- Set mode
      set_mode = function(mode)
        _G.vim._current_mode = mode
      end,

      -- Set cursor position
      set_cursor = function(win, row, col)
        if not _G.vim._windows[win] then
          _G.vim._windows[win] = {}
        end
        _G.vim._windows[win].cursor = { row, col }
      end,

      -- Add a buffer
      add_buffer = function(bufnr, name, content)
        local lines = {}
        if type(content) == "string" then
          for line in content:gmatch("([^\n]*)\n?") do
            table.insert(lines, line)
          end
        elseif type(content) == "table" then
          lines = content
        end

        _G.vim._buffers[bufnr] = {
          name = name,
          lines = lines,
          options = {},
          listed = true,
        }
      end,
    },
  }

  -- Initialize with a test buffer
  _G.vim.test.add_buffer(1, "/path/to/test.lua", "local test = {}\nreturn test")
  _G.vim.test.set_cursor(1, 1, 0)
end

describe("Selection module", function()
  local selection
  local mock_server = {
    broadcast = function(event, data)
      -- Store last broadcast for testing
      mock_server.last_broadcast = {
        event = event,
        data = data,
      }
    end,
    last_broadcast = nil,
  }

  -- Set up before each test
  setup(function()
    -- Reset the module
    package.loaded["claudecode.selection"] = nil

    -- Load module
    selection = require("claudecode.selection")
  end)

  -- Clean up after each test
  teardown(function()
    if selection.state.tracking_enabled then
      selection.disable()
    end
    mock_server.last_broadcast = nil
  end)

  it("should have the correct initial state", function()
    assert.is_table(selection.state)
    assert.is_nil(selection.state.latest_selection)
    assert.is_false(selection.state.tracking_enabled)
    assert.is_nil(selection.state.debounce_timer)
    assert.is_number(selection.state.debounce_ms)
  end)

  it("should enable and disable tracking", function()
    -- Enable tracking
    selection.enable(mock_server)

    assert.is_true(selection.state.tracking_enabled)
    assert.equals(mock_server, selection.server)

    -- Disable tracking
    selection.disable()

    assert.is_false(selection.state.tracking_enabled)
    assert.is_nil(selection.server)
    assert.is_nil(selection.state.latest_selection)
  end)

  it("should get cursor position in normal mode", function()
    -- Set up mock environment
    local old_win_get_cursor = _G.vim.api.nvim_win_get_cursor
    _G.vim.api.nvim_win_get_cursor = function()
      return { 2, 3 } -- row 2, col 3 (1-based)
    end

    -- Set normal mode
    _G.vim.test.set_mode("n")

    local cursor_pos = selection.get_cursor_position()

    -- Restore original function
    _G.vim.api.nvim_win_get_cursor = old_win_get_cursor

    assert.is_table(cursor_pos)
    assert.equals("", cursor_pos.text)
    assert.is_string(cursor_pos.filePath)
    assert.is_string(cursor_pos.fileUrl)
    assert.is_table(cursor_pos.selection)
    assert.is_table(cursor_pos.selection.start)
    assert.is_table(cursor_pos.selection["end"])

    -- Check positions - 0-based in selection, source is 1-based from nvim_win_get_cursor
    assert.equals(1, cursor_pos.selection.start.line) -- Should be 2-1=1
    assert.equals(3, cursor_pos.selection.start.character)
    assert.equals(1, cursor_pos.selection["end"].line)
    assert.equals(3, cursor_pos.selection["end"].character)
    assert.is_true(cursor_pos.selection.isEmpty)
  end)

  it("should detect selection changes", function()
    local old_selection = {
      text = "test",
      filePath = "/path/file1.lua",
      fileUrl = "file:///path/file1.lua",
      selection = {
        start = { line = 1, character = 0 },
        ["end"] = { line = 1, character = 4 },
        isEmpty = false,
      },
    }

    local new_selection_same = {
      text = "test",
      filePath = "/path/file1.lua",
      fileUrl = "file:///path/file1.lua",
      selection = {
        start = { line = 1, character = 0 },
        ["end"] = { line = 1, character = 4 },
        isEmpty = false,
      },
    }

    local new_selection_diff_file = {
      text = "test",
      filePath = "/path/file2.lua",
      fileUrl = "file:///path/file2.lua",
      selection = {
        start = { line = 1, character = 0 },
        ["end"] = { line = 1, character = 4 },
        isEmpty = false,
      },
    }

    local new_selection_diff_text = {
      text = "test2",
      filePath = "/path/file1.lua",
      fileUrl = "file:///path/file1.lua",
      selection = {
        start = { line = 1, character = 0 },
        ["end"] = { line = 1, character = 5 },
        isEmpty = false,
      },
    }

    local new_selection_diff_pos = {
      text = "test",
      filePath = "/path/file1.lua",
      fileUrl = "file:///path/file1.lua",
      selection = {
        start = { line = 2, character = 0 },
        ["end"] = { line = 2, character = 4 },
        isEmpty = false,
      },
    }

    -- Set up latest selection
    selection.state.latest_selection = old_selection

    -- Test same selection
    assert.is_false(selection.has_selection_changed(new_selection_same))

    -- Test different file
    assert.is_true(selection.has_selection_changed(new_selection_diff_file))

    -- Test different text
    assert.is_true(selection.has_selection_changed(new_selection_diff_text))

    -- Test different position
    assert.is_true(selection.has_selection_changed(new_selection_diff_pos))
  end)
end)
