-- Minimal Neovim configuration for tests

-- Set up package path
local package_root = vim.fn.stdpath("data") .. "/site/pack/vendor/start/"
local install_path = package_root .. "plenary.nvim"

if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim",
    install_path,
  })
  vim.cmd([[packadd plenary.nvim]])
end

-- Add package paths for development
vim.opt.runtimepath:append(vim.fn.expand("$HOME/.local/share/nvim/site/pack/vendor/start/plenary.nvim"))
vim.opt.runtimepath:append(vim.fn.expand("$HOME/.local/share/nvim/site/pack/vendor/start/claudecode.nvim"))

-- Set up test environment
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.termguicolors = true
vim.opt.timeoutlen = 300
vim.opt.updatetime = 250

-- Disable some built-in plugins
local disabled_built_ins = {
  "gzip",
  "matchit",
  "matchparen",
  "netrwPlugin",
  "tarPlugin",
  "tohtml",
  "tutor",
  "zipPlugin",
}

for _, plugin in pairs(disabled_built_ins) do
  vim.g["loaded_" .. plugin] = 1
end

-- Set up plugin
if not vim.g.loaded_claudecode then
  require("claudecode").setup({
    auto_start = false,
    log_level = "trace", -- More verbose for tests
  })
end
