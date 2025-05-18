-- Mock implementation of the Neovim API for tests

local vim = {
  -- Mock values
  _buffers = {},
  _windows = {},
  _commands = {},
  _autocmds = {},
  _vars = {},
  _options = {},

  -- Mock API
  api = {
    -- Create user command
    nvim_create_user_command = function(name, callback, opts)
      vim._commands[name] = {
        callback = callback,
        opts = opts,
      }
    end,

    -- Create autocommand group
    nvim_create_augroup = function(name, opts)
      vim._autocmds[name] = {
        opts = opts,
        events = {},
      }
      return name
    end,

    -- Create autocommand
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

    -- Clear autocommands
    nvim_clear_autocmds = function(opts)
      if opts.group then
        vim._autocmds[opts.group] = nil
      end
    end,

    -- Get current buffer
    nvim_get_current_buf = function()
      return 1
    end,

    -- Get buffer name
    nvim_buf_get_name = function(bufnr)
      return vim._buffers[bufnr] and vim._buffers[bufnr].name or ""
    end,

    -- Check if buffer is loaded
    nvim_buf_is_loaded = function(bufnr)
      return vim._buffers[bufnr] ~= nil
    end,

    -- Get cursor position
    nvim_win_get_cursor = function(winid)
      return vim._windows[winid] and vim._windows[winid].cursor or { 1, 0 }
    end,

    -- Get buffer lines
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

    -- Get buffer option
    nvim_buf_get_option = function(bufnr, name)
      if not vim._buffers[bufnr] then
        return nil
      end

      return vim._buffers[bufnr].options and vim._buffers[bufnr].options[name] or nil
    end,

    -- List buffers
    nvim_list_bufs = function()
      local bufs = {}
      for bufnr, _ in pairs(vim._buffers) do
        table.insert(bufs, bufnr)
      end
      return bufs
    end,

    -- Delete buffer
    nvim_buf_delete = function(bufnr, opts)
      vim._buffers[bufnr] = nil
    end,

    -- Call function in buffer context
    nvim_buf_call = function(bufnr, callback)
      callback()
    end,

    -- Echo message
    nvim_echo = function(chunks, history, opts)
      -- Just store the last echo message for testing
      vim._last_echo = {
        chunks = chunks,
        history = history,
        opts = opts,
      }
    end,

    -- Error message
    nvim_err_writeln = function(msg)
      vim._last_error = msg
    end,
  },

  -- Mock fn functions
  fn = {
    -- Get PID
    getpid = function()
      return 12345
    end,

    -- Expand path
    expand = function(path)
      return path:gsub("~", "/home/user")
    end,

    -- Check if file is readable
    filereadable = function(path)
      -- Mock file check
      return 1
    end,

    -- Get buffer number
    bufnr = function(name)
      for bufnr, buf in pairs(vim._buffers) do
        if buf.name == name then
          return bufnr
        end
      end
      return -1
    end,

    -- Check if buffer is listed
    buflisted = function(bufnr)
      return vim._buffers[bufnr] and vim._buffers[bufnr].listed and 1 or 0
    end,

    -- Create directory
    mkdir = function(path, flags)
      -- Mock directory creation
      return 1
    end,

    -- Get visual selection start position
    getpos = function(mark)
      if mark == "'<" then
        return { 0, 1, 1, 0 }
      elseif mark == "'>" then
        return { 0, 1, 10, 0 }
      end
      return { 0, 0, 0, 0 }
    end,

    -- Get current mode
    mode = function()
      return "n"
    end,

    -- Escape filename
    fnameescape = function(name)
      return name:gsub(" ", "\\ ")
    end,

    -- Get current working directory
    getcwd = function()
      return "/home/user/project"
    end,

    -- Get filename modifier
    fnamemodify = function(path, modifier)
      if modifier == ":t" then
        return path:match("([^/]+)$") or path
      end
      return path
    end,

    -- Check if feature is available
    has = function(feature)
      if feature == "nvim-0.8.0" then
        return 1
      end
      return 0
    end,
  },

  -- Mock command function
  cmd = function(command)
    -- Store the last command for testing
    vim._last_command = command
  end,

  -- Mock json module
  json = {
    encode = function(data)
      -- Simple JSON encoding for testing
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
      -- This is just a stub - in real tests we would
      -- use a proper JSON library or a more sophisticated mock
      return {}
    end,
  },

  -- Mock global variable getter/setter
  g = setmetatable({}, {
    __index = function(_, key)
      return vim._vars[key]
    end,
    __newindex = function(_, key, value)
      vim._vars[key] = value
    end,
  }),

  -- Mock deep copy function
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

  -- Mock table extend function
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

  -- Loop module stub
  loop = {
    -- Timer functions
    timer_stop = function(timer)
      return true
    end,
  },

  -- Mock defer_fn
  defer_fn = function(fn, timeout)
    -- For testing, we'll execute immediately
    fn()
  end,

  -- Helper functions for tests to set up mock state
  _mock = {
    -- Add a buffer to the mock
    add_buffer = function(bufnr, name, content, opts)
      vim._buffers[bufnr] = {
        name = name,
        lines = type(content) == "string" and vim._mock.split_lines(content) or content,
        options = opts or {},
        listed = true,
      }
    end,

    -- Split string into lines
    split_lines = function(str)
      local lines = {}
      for line in str:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end
      return lines
    end,

    -- Set up a window
    add_window = function(winid, bufnr, cursor)
      vim._windows[winid] = {
        buffer = bufnr,
        cursor = cursor or { 1, 0 },
      }
    end,

    -- Reset all mock state
    reset = function()
      vim._buffers = {}
      vim._windows = {}
      vim._commands = {}
      vim._autocmds = {}
      vim._vars = {}
      vim._options = {}
      vim._last_command = nil
      vim._last_echo = nil
      vim._last_error = nil
    end,
  },
}

-- Initialize with some mock state
vim._mock.add_buffer(1, "/home/user/project/test.lua", "local test = {}\nreturn test")
vim._mock.add_window(0, 1, { 1, 0 })

return vim
