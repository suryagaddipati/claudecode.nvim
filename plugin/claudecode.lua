if vim.fn.has("nvim-0.8.0") ~= 1 then
  vim.api.nvim_err_writeln("Claude Code requires Neovim >= 0.8.0")
  return
end

if vim.g.loaded_claudecode then
  return
end
vim.g.loaded_claudecode = 1

-- Example in init.lua: vim.g.claudecode_auto_setup = { auto_start = true }
if vim.g.claudecode_auto_setup then
  vim.defer_fn(function()
    require("claudecode").setup(vim.g.claudecode_auto_setup)
  end, 0)
end

local terminal_ok, terminal = pcall(require, "claudecode.terminal")

if terminal_ok then
  vim.api.nvim_create_user_command("ClaudeCode", function(_opts)
    local current_mode = vim.fn.mode()
    if current_mode == "v" or current_mode == "V" or current_mode == "\22" then -- \22 is CTRL-V for blockwise visual
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end
    terminal.toggle({}) -- opts.fargs could be used for future enhancements
  end, {
    nargs = "?", -- Allow optional arguments for future enhancements
    desc = "Toggle the Claude Code terminal window",
  })

  vim.api.nvim_create_user_command("ClaudeCodeOpen", function(_opts)
    terminal.open({}) -- opts.fargs could be used for future enhancements
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
