-- Claude Code Neovim Integration
-- Plugin entry point

-- Check if Neovim version is compatible
if vim.fn.has("nvim-0.8.0") ~= 1 then
  vim.api.nvim_err_writeln("Claude Code requires Neovim >= 0.8.0")
  return
end

-- Prevent loading the plugin multiple times
if vim.g.loaded_claudecode then
  return
end

-- Mark as loaded
vim.g.loaded_claudecode = 1

-- Create user-facing commands
vim.api.nvim_create_user_command("ClaudeCodeSetup", function(opts)
  require("claudecode").setup(opts.args ~= "" and loadstring("return " .. opts.args)() or {})
end, {
  desc = "Set up Claude Code integration with optional configuration",
  nargs = "?",
  complete = function()
    return {
      "auto_start = true",
      'log_level = "debug"',
      "track_selection = true",
    }
  end,
})

-- If the user has set auto-load configuration, load it
-- Example in init.lua: vim.g.claudecode_auto_setup = { auto_start = true }
if vim.g.claudecode_auto_setup then
  vim.defer_fn(function()
    require("claudecode").setup(vim.g.claudecode_auto_setup)
  end, 0)
end
