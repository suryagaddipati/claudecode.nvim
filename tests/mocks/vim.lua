-- Mock implementation of the Neovim API for tests

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
      -- Just store the last echo message for testing
      vim._last_echo = {
        chunks = chunks,
        history = history,
        opts = opts,
      }
    end,

    nvim_err_writeln = function(msg)
      vim._last_error = msg
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
  },

  cmd = function(command)
    -- Store the last command for testing
    vim._last_command = command
  end,

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

  -- Loop module stub
  loop = {
    timer_stop = function(timer)
      return true
    end,
  },

  defer_fn = function(fn, timeout)
    -- For testing, we'll execute immediately
    fn()
  end,

  log = {
    levels = {
      TRACE = 0,
      DEBUG = 1,
      INFO = 2,
      WARN = 3,
      ERROR = 4,
    },
    -- Mock actual vim.log function if needed, e.g., vim.log.debug(...)
    -- For now, just providing levels for vim.notify
    trace = function(...) end,
    debug = function(...) end,
    info = function(...) end,
    warn = function(...) end,
    error = function(...) end,
  },

  -- Helper functions for tests to set up mock state
  _mock = {
    add_buffer = function(bufnr, name, content, opts)
      -- Use 'self' reference instead of global vim
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

-- Initialize with some mock state once vim is assigned to _G
if _G.vim == nil then
  _G.vim = vim -- Ensure the global vim is set before initialization
end
-- Initialize buffers and windows after _G.vim is defined
vim._mock.add_buffer(1, "/home/user/project/test.lua", "local test = {}\nreturn test")
vim._mock.add_window(0, 1, { 1, 0 })

return vim
