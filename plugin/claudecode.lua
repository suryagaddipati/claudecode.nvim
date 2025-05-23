if vim.fn.has("nvim-0.8.0") ~= 1 then
  vim.api.nvim_err_writeln("Claude Code requires Neovim >= 0.8.0")
  return
end

if vim.g.loaded_claudecode then
  return
end
vim.g.loaded_claudecode = 1

--- Example: In your `init.lua`, you can set `vim.g.claudecode_auto_setup = { auto_start = true }`
--- to automatically start ClaudeCode when Neovim loads.
if vim.g.claudecode_auto_setup then
  vim.defer_fn(function()
    require("claudecode").setup(vim.g.claudecode_auto_setup)
  end, 0)
end

local terminal_ok, terminal = pcall(require, "claudecode.terminal")
local selection_module_ok, selection = pcall(require, "claudecode.selection")

if terminal_ok then
  vim.api.nvim_create_user_command("ClaudeCode", function(_opts)
    local current_mode = vim.fn.mode()
    if current_mode == "v" or current_mode == "V" or current_mode == "\22" then -- \22 is CTRL-V (blockwise visual mode)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end
    terminal.toggle({}) -- `opts.fargs` can be used for future enhancements, e.g., passing initial prompts.
  end, {
    nargs = "?", -- Allows optional arguments, useful for future command enhancements.
    desc = "Toggle the Claude Code terminal window",
  })

  vim.api.nvim_create_user_command("ClaudeCodeOpen", function(_opts)
    terminal.open({}) -- `opts.fargs` can be used for future enhancements.
  end, {
    nargs = "?",
    desc = "Open the Claude Code terminal window",
  })

  vim.api.nvim_create_user_command("ClaudeCodeClose", function()
    terminal.close()
  end, {
    desc = "Close the Claude Code terminal window",
  })
else
  vim.notify("ClaudeCode Terminal module not found. Commands not registered.", vim.log.levels.ERROR)
end
if selection_module_ok then
  vim.api.nvim_create_user_command("ClaudeCodeSend", function(opts)
    if opts.range == 0 then
      vim.api.nvim_err_writeln("ClaudeCodeSend requires a visual selection.")
      return
    end
    -- While `opts.line1` and `opts.line2` provide the selected line range,
    -- the `selection` module is preferred for obtaining precise character data if needed.
    selection.send_at_mention_for_visual_selection()
  end, {
    desc = "Send the current visual selection as an at_mention to Claude",
    range = true, -- This is crucial for commands that operate on a visual selection (e.g., :'&lt;,'&gt;Cmd).
  })
else
  vim.notify("ClaudeCode Selection module not found. ClaudeCodeSend command not registered.", vim.log.levels.ERROR)
end
