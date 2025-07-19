--- ToggleTerm.nvim terminal provider for Claude Code.
-- @module claudecode.terminal.toggleterm

--- @type TerminalProvider
local M = {}

local toggleterm_available, toggleterm = pcall(require, "toggleterm")
local Terminal
if toggleterm_available then
  Terminal = require("toggleterm.terminal").Terminal
end

local utils = require("claudecode.utils")
local claude_terminal = nil

--- @return boolean
local function is_available()
  return toggleterm_available and toggleterm and Terminal
end

--- Setup event handlers for terminal instance
--- @param config table Configuration options
--- @return function|nil on_exit callback for ToggleTerm constructor
local function get_on_exit_callback(config)
  local logger = require("claudecode.logger")

  -- Handle command completion/exit - only if auto_close is enabled
  if config.auto_close then
    return function(term)
      if vim.v.event and vim.v.event.status and vim.v.event.status ~= 0 then
        logger.error("terminal", "Claude exited with code " .. vim.v.event.status .. ".\nCheck for any errors.")
      end

      -- Clean up
      claude_terminal = nil
      vim.schedule(function()
        if term and term.close then
          term:close()
        end
        vim.cmd.checktime()
      end)
    end
  end
  return nil
end

--- Determine the terminal direction based on configuration
--- @param config table Terminal configuration
--- @return string direction ToggleTerm direction ("vertical", "horizontal", "float", "tab")
local function determine_direction(config)
  -- Use explicit direction if provided
  if config.direction then
    return config.direction
  end
  
  -- Legacy support: map split_side to direction
  if config.split_side then
    return "vertical"
  end
  
  return "vertical" -- Default fallback
end

--- Calculate terminal size based on direction and configuration
--- @param config table Terminal configuration
--- @param direction string ToggleTerm direction
--- @return number|nil size Size for ToggleTerm (nil for float/tab directions)
local function calculate_size(config, direction)
  -- Use custom size function if provided
  if config.size_function and type(config.size_function) == "function" then
    return config.size_function(direction)
  end
  
  if direction == "vertical" then
    local width_percentage = config.split_width_percentage or 0.30
    return math.floor(vim.o.columns * width_percentage)
  elseif direction == "horizontal" then
    local height_percentage = config.split_height_percentage or 0.30
    return math.floor(vim.o.lines * height_percentage)
  elseif direction == "float" or direction == "tab" then
    return nil -- Size handled differently for these directions
  end
  
  return math.floor(vim.o.columns * 0.30) -- Fallback
end

--- Build float window options
--- @param config table Terminal configuration
--- @return table|nil float_opts Float window options or nil if not float direction
local function build_float_opts(config)
  if config.direction ~= "float" then
    return nil
  end
  
  local float_opts = config.float_opts or {}
  
  return {
    border = float_opts.border or "curved",
    width = float_opts.width or math.floor(vim.o.columns * 0.8),
    height = float_opts.height or math.floor(vim.o.lines * 0.8),
    row = float_opts.row or math.floor(vim.o.lines * 0.1),
    col = float_opts.col or math.floor(vim.o.columns * 0.1),
    winblend = float_opts.winblend or 0,
    zindex = float_opts.zindex or 1000,
  }
end

--- Set vim split settings for proper positioning
--- @param config table Terminal configuration
--- @param direction string ToggleTerm direction
--- @return table original_settings Original vim settings to restore later
local function set_split_settings(config, direction)
  local original_settings = {}
  
  if direction == "vertical" and config.split_side then
    -- Save current setting
    original_settings.splitright = vim.opt.splitright:get()
    
    -- Set desired split side
    if config.split_side == "left" then
      vim.opt.splitright = false
    else
      vim.opt.splitright = true
    end
  elseif direction == "horizontal" and config.split_side then
    -- Support top/bottom positioning for horizontal splits
    original_settings.splitbelow = vim.opt.splitbelow:get()
    
    if config.split_side == "top" then
      vim.opt.splitbelow = false
    else
      vim.opt.splitbelow = true
    end
  end
  
  return original_settings
end

--- Restore vim split settings
--- @param original_settings table Original vim settings to restore
local function restore_split_settings(original_settings)
  if original_settings.splitright ~= nil then
    vim.opt.splitright = original_settings.splitright
  end
  if original_settings.splitbelow ~= nil then
    vim.opt.splitbelow = original_settings.splitbelow
  end
end

--- Builds ToggleTerm terminal options
--- @param cmd_string string Command to run in terminal
--- @param config table Terminal configuration (split_side, split_width_percentage, etc.)
--- @param env_table table Environment variables to set for the terminal process
--- @param focus boolean|nil Whether to focus the terminal when opened (defaults to true)
--- @return table ToggleTerm terminal options
--- @return table original_settings Original vim settings to restore after terminal creation
local function build_terminal_opts(cmd_string, config, env_table, focus)
  focus = utils.normalize_focus(focus)
  
  local direction = determine_direction(config)
  local size = calculate_size(config, direction)
  local on_exit_callback = get_on_exit_callback(config)
  local float_opts = build_float_opts(config)
  
  -- Set vim split settings for proper positioning
  local original_settings = set_split_settings(config, direction)
  
  local opts = {
    cmd = cmd_string,
    hidden = true, -- Prevent global ToggleTerm commands from affecting this terminal
    direction = direction,
    close_on_exit = false, -- We handle this manually via config.auto_close
    -- Use a specific count to avoid conflicts with user's regular terminals
    count = 99, -- High number to avoid conflicts
    on_open = function(term)
      local map_opts = {buffer = term.bufnr}
      -- Give Escape key to Claude Code instead of exiting terminal mode
      vim.keymap.set('t', '<Esc>', '<Esc>', map_opts)  -- Pass through to Claude
      -- Use Ctrl+\ Ctrl+n to exit terminal mode instead
      vim.keymap.set('t', '<C-\\><C-n>', '<C-\\><C-n>', map_opts)
    end,
  }
  
  -- Add size if applicable (not for float/tab directions)
  if size then
    opts.size = size
  end
  
  -- Add float window options if applicable
  if float_opts then
    opts.float_opts = float_opts
  end
  
  -- Add optional parameters
  if on_exit_callback then
    opts.on_exit = on_exit_callback
  end
  
  -- Environment variables support
  -- Note: ToggleTerm may handle env differently, try direct assignment first
  if env_table then
    opts.env = env_table
  end
  
  return opts, original_settings
end

function M.setup()
  -- No specific setup needed for ToggleTerm provider
end

--- @param cmd_string string
--- @param env_table table
--- @param config table
--- @param focus boolean|nil
function M.open(cmd_string, env_table, config, focus)
  if not is_available() then
    vim.notify("ToggleTerm.nvim terminal provider selected but ToggleTerm not available.", vim.log.levels.ERROR)
    return
  end

  focus = utils.normalize_focus(focus)

  -- If terminal already exists and is valid
  if claude_terminal and claude_terminal.window and vim.api.nvim_win_is_valid(claude_terminal.window) then
    -- Terminal exists and is visible
    if focus then
      claude_terminal:focus()
      -- Enter insert mode if in terminal buffer
      local bufnr = claude_terminal.bufnr
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buftype") == "terminal" then
        vim.schedule(function()
          vim.cmd("startinsert")
        end)
      end
    end
    return
  elseif claude_terminal and (not claude_terminal.window or not vim.api.nvim_win_is_valid(claude_terminal.window)) then
    -- Terminal exists but is hidden, show it
    claude_terminal:toggle()
    if focus then
      claude_terminal:focus()
      local bufnr = claude_terminal.bufnr
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buftype") == "terminal" then
        vim.schedule(function()
          vim.cmd("startinsert")
        end)
      end
    end
    return
  end

  -- Create new terminal
  local opts, original_settings = build_terminal_opts(cmd_string, config, env_table, focus)
  local term_instance = Terminal:new(opts)
  
  if term_instance then
    claude_terminal = term_instance
    
    -- Open the terminal
    term_instance:open()
    
    -- Restore vim split settings after terminal creation
    restore_split_settings(original_settings)
    
    if focus then
      term_instance:focus()
      vim.schedule(function()
        vim.cmd("startinsert")
      end)
    end
  else
    claude_terminal = nil
    local logger = require("claudecode.logger")
    local error_msg = string.format(
      "Failed to create Claude terminal using ToggleTerm. Command: %s",
      cmd_string
    )
    vim.notify(error_msg, vim.log.levels.ERROR)
    logger.debug("terminal", error_msg)
  end
end

function M.close()
  if not is_available() then
    return
  end
  if claude_terminal and claude_terminal.close then
    claude_terminal:close()
  end
end

--- Simple toggle: always show/hide terminal regardless of focus
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.simple_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("ToggleTerm.nvim terminal provider selected but ToggleTerm not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  -- Check if terminal exists and is visible
  if claude_terminal and claude_terminal.window and vim.api.nvim_win_is_valid(claude_terminal.window) then
    -- Terminal is visible, hide it
    logger.debug("terminal", "Simple toggle: hiding visible terminal")
    claude_terminal:toggle()
  elseif claude_terminal and (not claude_terminal.window or not vim.api.nvim_win_is_valid(claude_terminal.window)) then
    -- Terminal exists but not visible, show it
    logger.debug("terminal", "Simple toggle: showing hidden terminal")
    claude_terminal:toggle()
  else
    -- No terminal exists, create new one
    logger.debug("terminal", "Simple toggle: creating new terminal")
    M.open(cmd_string, env_table, config, false) -- Don't auto-focus on toggle
  end
end

--- Smart focus toggle: switches to terminal if not focused, hides if currently focused
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.focus_toggle(cmd_string, env_table, config)
  if not is_available() then
    vim.notify("ToggleTerm.nvim terminal provider selected but ToggleTerm not available.", vim.log.levels.ERROR)
    return
  end

  local logger = require("claudecode.logger")

  -- Terminal exists but not visible
  if claude_terminal and (not claude_terminal.window or not vim.api.nvim_win_is_valid(claude_terminal.window)) then
    logger.debug("terminal", "Focus toggle: showing hidden terminal")
    claude_terminal:toggle()
    claude_terminal:focus()
    vim.schedule(function()
      vim.cmd("startinsert")
    end)
  -- Terminal exists and is visible
  elseif claude_terminal and claude_terminal.window and vim.api.nvim_win_is_valid(claude_terminal.window) then
    local current_win = vim.api.nvim_get_current_win()
    local claude_win = nil
    
    -- Find the terminal window
    if claude_terminal.window then
      claude_win = claude_terminal.window
    end
    
    -- Check if we're currently in the terminal window
    if claude_win and current_win == claude_win then
      logger.debug("terminal", "Focus toggle: hiding terminal (currently focused)")
      claude_terminal:toggle()
    else
      logger.debug("terminal", "Focus toggle: focusing terminal")
      claude_terminal:focus()
      vim.schedule(function()
        vim.cmd("startinsert")
      end)
    end
  -- No terminal exists
  else
    logger.debug("terminal", "Focus toggle: creating new terminal")
    M.open(cmd_string, env_table, config, true) -- Auto-focus new terminal
  end
end

--- Legacy toggle function for backward compatibility (defaults to simple_toggle)
--- @param cmd_string string
--- @param env_table table
--- @param config table
function M.toggle(cmd_string, env_table, config)
  M.simple_toggle(cmd_string, env_table, config)
end

--- @return number|nil
function M.get_active_bufnr()
  if claude_terminal and claude_terminal.bufnr then
    if vim.api.nvim_buf_is_valid(claude_terminal.bufnr) then
      return claude_terminal.bufnr
    end
  end
  return nil
end

--- @return boolean
function M.is_available()
  return is_available()
end

-- For testing purposes
--- @return table|nil
function M._get_terminal_for_test()
  return claude_terminal
end

return M