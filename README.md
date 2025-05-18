# Claude Code Neovim Integration

[![Tests](https://github.com/ThomasK33/claudecode.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/ThomasK33/claudecode.nvim/actions/workflows/test.yml)
![Neovim version](https://img.shields.io/badge/Neovim-0.8%2B-green)
![Status](https://img.shields.io/badge/Status-alpha-orange)

A Neovim plugin that integrates with Claude Code CLI to provide a seamless AI coding experience in Neovim.

## Features

- 🔄 Bidirectional communication with Claude Code CLI
- 🔍 Selection tracking to provide context to Claude
- 🛠️ Integration with Neovim's buffer and window management
- 📝 Support for file operations and diagnostics
- 🖥️ Terminal integration for launching Claude with proper environment

## Requirements

- Neovim >= 0.8.0
- Claude Code CLI installed and in your PATH
- Lua >= 5.1
- Optional: plenary.nvim for additional utilities

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ThomasK33/claudecode.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("claudecode").setup({
      -- Optional configuration
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ThomasK33/claudecode.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("claudecode").setup({
      -- Optional configuration
    })
  end
}
```

### Using [LazyVim](https://github.com/LazyVim/LazyVim)

Add the following to your `lua/plugins/claudecode.lua`:

```lua
return {
  {
    "ThomasK33/claudecode.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    opts = {
      -- Optional configuration
    },
    keys = {
      { "<leader>cc", "<cmd>ClaudeCodeStart<cr>", desc = "Start Claude Code" },
      { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", desc = "Send to Claude Code" },
    },
  },
}
```

## Configuration

```lua
require("claudecode").setup({
  -- Port range for WebSocket server (default: 10000-65535)
  port_range = { min = 10000, max = 65535 },

  -- Auto-start WebSocket server on Neovim startup
  auto_start = false,

  -- Custom terminal command to use when launching Claude
  terminal_cmd = nil, -- e.g., "toggleterm"

  -- Log level (trace, debug, info, warn, error)
  log_level = "info",

  -- Enable sending selection updates to Claude
  track_selection = true,
})
```

## Usage

1. Start the Claude Code integration:

   ```
   :ClaudeCodeStart
   ```

2. This will start a WebSocket server and provide a command to launch Claude Code CLI with the proper environment variables.

3. Send the current selection to Claude:

   ```
   :ClaudeCodeSend
   ```

4. Use Claude as normal - it will have access to your Neovim editor context!

## Commands

- `:ClaudeCodeStart` - Start the Claude Code integration server
- `:ClaudeCodeStop` - Stop the server
- `:ClaudeCodeStatus` - Show connection status
- `:ClaudeCodeSend` - Send current selection to Claude

## Keymaps

No default keymaps are provided. Add your own in your configuration:

```lua
vim.keymap.set("n", "<leader>cc", "<cmd>ClaudeCodeStart<cr>", { desc = "Start Claude Code" })
vim.keymap.set({"n", "v"}, "<leader>cs", "<cmd>ClaudeCodeSend<cr>", { desc = "Send to Claude Code" })
```

## Architecture

The plugin follows a modular architecture with these main components:

1. **WebSocket Server** - Handles communication with Claude Code CLI using JSON-RPC 2.0 protocol
2. **Lock File System** - Creates and manages lock files that Claude CLI uses to detect the editor integration
3. **Selection Tracking** - Monitors text selections and cursor position in Neovim
4. **Tool Implementations** - Implements commands that Claude can execute in the editor

For more details, see [ARCHITECTURE.md](./ARCHITECTURE.md).

## Developing Locally

This project uses [Nix](https://nixos.org/) for development environment management. For the best experience:

1. Install Nix with flakes support
2. Clone the repository:

   ```bash
   git clone https://github.com/ThomasK33/claudecode.nvim
   cd claudecode.nvim
   ```

3. Enter the development shell:

   ```bash
   nix develop
   # Or use direnv if available
   direnv allow
   ```

4. Run development commands:

   ```bash
   # Format code
   nix fmt

   # Check code for errors
   make check

   # Run tests
   make test
   ```

5. Link to your Neovim plugins directory:

   ```bash
   # For traditional package managers
   ln -s $(pwd) ~/.local/share/nvim/site/pack/plugins/start/claudecode.nvim

   # For Lazy
   ln -s $(pwd) ~/.local/share/nvim/lazy/claudecode.nvim
   ```

Without Nix, ensure you have:

- Lua 5.1+
- LuaCheck for linting
- StyLua for formatting
- Busted for testing

## Troubleshooting

### Connection Issues

If Claude isn't connecting to Neovim:

1. Check if the WebSocket server is running: `:ClaudeCodeStatus`
2. Verify lock file exists in `~/.claude/ide/`
3. Check that Claude CLI has the right environment variables set

### Debug Mode

Enable more detailed logging:

```lua
require("claudecode").setup({
  log_level = "debug",
})
```

## Contributing

Contributions are welcome! Please see [DEVELOPMENT.md](./DEVELOPMENT.md) for development guidelines.

## License

MIT

## Acknowledgements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) by Anthropic
- Based on research from analyzing the [VS Code extension](https://github.com/anthropic-labs/vscode-mcp)
