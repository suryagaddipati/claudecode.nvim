--- Mock implementation of the Neovim API for tests.

--- Spy functionality for testing.
--- Provides a `spy.on` method to wrap functions and track their calls.
if _G.spy == nil then
  _G.spy = {
    on = function(table, method_name)
      local original = table[method_name]
      local calls = {}

      table[method_name] = function(...)
        table.insert(calls, { vals = { ... } })
        if original then
          return original(...)
        end
      end

      table[method_name].calls = calls
      table[method_name].spy = function()
        return {
          was_called = function(n)
            assert(#calls == n, "Expected " .. n .. " calls, got " .. #calls)
            return true
          end,
          was_not_called = function()
            assert(#calls == 0, "Expected 0 calls, got " .. #calls)
            return true
          end,
          was_called_with = function(...)
            local expected = { ... }
            assert(#calls > 0, "Function was never called")

            local last_call = calls[#calls].vals
            for i, v in ipairs(expected) do
              if type(v) == "table" and v._type == "match" then
                -- Use custom matcher (simplified for this mock)
                if v._match == "is_table" and type(last_call[i]) ~= "table" then
                  assert(false, "Expected table at arg " .. i)
                end
              else
                assert(last_call[i] == v, "Argument mismatch at position " .. i)
              end
            end
            return true
          end,
        }
      end

      return table[method_name]
    end,
  }

  --- Simple table matcher for spy assertions.
  --- Allows checking if an argument was a table.
  _G.match = {
    is_table = function()
      return { _type = "match", _match = "is_table" }
    end,
  }
end

local vim = {
  _buffers = {},
  _windows = {},
  _commands = {},
  _autocmds = {},
  _vars = {},
  _options = {},

  api = {
    nvim_create_user_command = function(name, callback, opts)
      vim._commands[name] = {
        callback = callback,
        opts = opts,
      }
    end,

    nvim_create_augroup = function(name, opts)
      vim._autocmds[name] = {
        opts = opts,
        events = {},
      }
      return name
    end,

    nvim_create_autocmd = function(events, opts)
      local group = opts.group or "default"
      if not vim._autocmds[group] then
        vim._autocmds[group] = {
          opts = {},
          events = {},
        }
      end

      local id = #vim._autocmds[group].events + 1
      vim._autocmds[group].events[id] = {
        events = events,
        opts = opts,
      }

      return id
    end,

    nvim_clear_autocmds = function(opts)
      if opts.group then
        vim._autocmds[opts.group] = nil
      end
    end,

    nvim_get_current_buf = function()
      return 1
    end,

    nvim_buf_get_name = function(bufnr)
      return vim._buffers[bufnr] and vim._buffers[bufnr].name or ""
    end,

    nvim_buf_is_loaded = function(bufnr)
      return vim._buffers[bufnr] ~= nil
    end,

    nvim_win_get_cursor = function(winid)
      return vim._windows[winid] and vim._windows[winid].cursor or { 1, 0 }
    end,

    nvim_buf_get_lines = function(bufnr, start, end_line, strict)
      if not vim._buffers[bufnr] then
        return {}
      end

      local lines = vim._buffers[bufnr].lines or {}
      local result = {}

      for i = start + 1, end_line do
        table.insert(result, lines[i] or "")
      end

      return result
    end,

    nvim_buf_get_option = function(bufnr, name)
      if not vim._buffers[bufnr] then
        return nil
      end

      return vim._buffers[bufnr].options and vim._buffers[bufnr].options[name] or nil
    end,

    nvim_list_bufs = function()
      local bufs = {}
      for bufnr, _ in pairs(vim._buffers) do
        table.insert(bufs, bufnr)
      end
      return bufs
    end,

    nvim_buf_delete = function(bufnr, opts)
      vim._buffers[bufnr] = nil
    end,

    nvim_buf_call = function(bufnr, callback)
      callback()
    end,

    nvim_echo = function(chunks, history, opts)
      -- Store the last echo message for test assertions.
      vim._last_echo = {
        chunks = chunks,
        history = history,
        opts = opts,
      }
    end,

    nvim_err_writeln = function(msg)
      vim._last_error = msg
    end,
    nvim_buf_set_name = function(bufnr, name)
      if vim._buffers[bufnr] then
        vim._buffers[bufnr].name = name
      else
        -- TODO: Consider if error handling for 'buffer not found' is needed for tests.
      end
    end,
    nvim_set_option_value = function(name, value, opts)
      -- Note: This mock simplifies 'scope = "local"' handling.
      -- In a real nvim_set_option_value, 'local' scope would apply to a specific
      -- buffer or window. Here, it's stored in a general options table if not
      -- a buffer-local option, or in the buffer's options table if `opts.buf` is provided.
      -- A more complex mock might be needed for intricate scope-related tests.
      if opts and opts.scope == "local" and opts.buf then
        if vim._buffers[opts.buf] then
          if not vim._buffers[opts.buf].options then
            vim._buffers[opts.buf].options = {}
          end
          vim._buffers[opts.buf].options[name] = value
        else
          -- TODO: Consider if error handling for 'buffer not found' is needed for tests.
        end
      else
        vim._options[name] = value
      end
    end,
  },

  fn = {
    getpid = function()
      return 12345
    end,

    expand = function(path)
      return path:gsub("~", "/home/user")
    end,

    filereadable = function(path)
      return 1
    end,

    bufnr = function(name)
      for bufnr, buf in pairs(vim._buffers) do
        if buf.name == name then
          return bufnr
        end
      end
      return -1
    end,

    buflisted = function(bufnr)
      return vim._buffers[bufnr] and vim._buffers[bufnr].listed and 1 or 0
    end,

    mkdir = function(path, flags)
      return 1
    end,

    getpos = function(mark)
      if mark == "'<" then
        return { 0, 1, 1, 0 }
      elseif mark == "'>" then
        return { 0, 1, 10, 0 }
      end
      return { 0, 0, 0, 0 }
    end,

    mode = function()
      return "n"
    end,

    fnameescape = function(name)
      return name:gsub(" ", "\\ ")
    end,

    getcwd = function()
      return "/home/user/project"
    end,

    fnamemodify = function(path, modifier)
      if modifier == ":t" then
        return path:match("([^/]+)$") or path
      end
      return path
    end,

    has = function(feature)
      if feature == "nvim-0.8.0" then
        return 1
      end
      return 0
    end,
    stdpath = function(type)
      if type == "cache" then
        return "/tmp/nvim_mock_cache"
      elseif type == "config" then
        return "/tmp/nvim_mock_config"
      elseif type == "data" then
        return "/tmp/nvim_mock_data"
      elseif type == "temp" then
        return "/tmp"
      else
        return "/tmp/nvim_mock_stdpath_" .. type
      end
    end,
    tempname = function()
      -- Return a somewhat predictable temporary name for testing.
      -- The random number ensures some uniqueness if called multiple times.
      return "/tmp/nvim_mock_tempfile_" .. math.random(1, 100000)
    end,
  },

  cmd = function(command)
    -- Store the last command for test assertions.
    vim._last_command = command
  end,

  json = {
    encode = function(data)
      -- Extremely simplified JSON encoding, sufficient for basic test cases.
      -- Does not handle all JSON types or edge cases.
      if type(data) == "table" then
        local parts = {}
        for k, v in pairs(data) do
          local val
          if type(v) == "string" then
            val = '"' .. v .. '"'
          elseif type(v) == "table" then
            val = vim.json.encode(v)
          else
            val = tostring(v)
          end

          if type(k) == "number" then
            table.insert(parts, val)
          else
            table.insert(parts, '"' .. k .. '":' .. val)
          end
        end

        if #parts > 0 and type(next(data)) == "number" then
          return "[" .. table.concat(parts, ",") .. "]"
        else
          return "{" .. table.concat(parts, ",") .. "}"
        end
      elseif type(data) == "string" then
        return '"' .. data .. '"'
      else
        return tostring(data)
      end
    end,

    decode = function(json_str)
      -- This is a non-functional stub for `vim.json.decode`.
      -- If tests require actual JSON decoding, a proper library or a more
      -- sophisticated mock implementation would be necessary.
      return {}
    end,
  },

  g = setmetatable({}, {
    __index = function(_, key)
      return vim._vars[key]
    end,
    __newindex = function(_, key, value)
      vim._vars[key] = value
    end,
  }),

  deepcopy = function(tbl)
    if type(tbl) ~= "table" then
      return tbl
    end

    local copy = {}
    for k, v in pairs(tbl) do
      if type(v) == "table" then
        copy[k] = vim.deepcopy(v)
      else
        copy[k] = v
      end
    end

    return copy
  end,

  tbl_deep_extend = function(behavior, ...)
    local result = {}
    local tables = { ... }

    for _, tbl in ipairs(tables) do
      for k, v in pairs(tbl) do
        if type(v) == "table" and type(result[k]) == "table" then
          result[k] = vim.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = v
        end
      end
    end

    return result
  end,

  --- Stub for the `vim.loop` module.
  --- Provides minimal implementations for TCP and timer functionalities
  --- required by some plugin tests.
  loop = {
    new_tcp = function()
      return {
        bind = function(self, host, port)
          return true
        end,
        listen = function(self, backlog, callback)
          return true
        end,
        accept = function(self, client)
          return true
        end,
        read_start = function(self, callback)
          return true
        end,
        write = function(self, data, callback)
          if callback then
            callback()
          end
          return true
        end,
        close = function(self)
          return true
        end,
        is_closing = function(self)
          return false
        end,
      }
    end,
    new_timer = function()
      return {
        start = function(self, timeout, repeat_interval, callback)
          return true
        end,
        stop = function(self)
          return true
        end,
        close = function(self)
          return true
        end,
      }
    end,
    now = function()
      return os.time() * 1000
    end,
    timer_stop = function(timer)
      return true
    end,
  },

  schedule = function(callback)
    callback()
  end,

  defer_fn = function(fn, timeout)
    -- For testing purposes, this mock executes the deferred function immediately
    -- instead of after a timeout.
    fn()
  end,

  notify = function(msg, level, opts)
    -- Store the last notification for test assertions.
    vim._last_notify = {
      msg = msg,
      level = level,
      opts = opts,
    }
    -- Return a mock notification ID, as some code might expect a return value.
    return 1
  end,

  log = {
    levels = {
      TRACE = 0,
      DEBUG = 1,
      INFO = 2,
      WARN = 3,
      ERROR = 4,
    },
    -- Provides log level constants, similar to `vim.log.levels`.
    -- The actual logging functions (trace, debug, etc.) are no-ops in this mock.
    -- These are primarily for `vim.notify` level compatibility if used.
    trace = function(...) end,
    debug = function(...) end,
    info = function(...) end,
    warn = function(...) end,
    error = function(...) end,
  },

  --- Internal helper functions for tests to manipulate the mock's state.
  --- These are not part of the Neovim API but are useful for setting up
  --- specific scenarios for testing plugins.
  _mock = {
    add_buffer = function(bufnr, name, content, opts)
      _G.vim._buffers[bufnr] = {
        name = name,
        lines = type(content) == "string" and _G.vim._mock.split_lines(content) or content,
        options = opts or {},
        listed = true,
      }
    end,

    split_lines = function(str)
      local lines = {}
      for line in str:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end
      return lines
    end,

    add_window = function(winid, bufnr, cursor)
      _G.vim._windows[winid] = {
        buffer = bufnr,
        cursor = cursor or { 1, 0 },
      }
    end,

    reset = function()
      _G.vim._buffers = {}
      _G.vim._windows = {}
      _G.vim._commands = {}
      _G.vim._autocmds = {}
      _G.vim._vars = {}
      _G.vim._options = {}
      _G.vim._last_command = nil
      _G.vim._last_echo = nil
      _G.vim._last_error = nil
    end,
  },
}

if _G.vim == nil then
  _G.vim = vim
end
vim._mock.add_buffer(1, "/home/user/project/test.lua", "local test = {}\nreturn test")
vim._mock.add_window(0, 1, { 1, 0 })

return vim
