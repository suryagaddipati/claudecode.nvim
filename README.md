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
- 🖥️ Interactive vertical split terminal for Claude sessions (supports `folke/snacks.nvim` or native Neovim terminal)
- 🔒 Automatic cleanup on exit - server shutdown and lockfile removal

## Requirements

- Neovim >= 0.8.0
- Claude Code CLI installed and in your PATH
- Lua >= 5.1
- **Optional for terminal integration:** [folke/snacks.nvim](https://github.com/folke/snacks.nvim) - Terminal management plugin (can use native Neovim terminal as an alternative).
- Optional: plenary.nvim for additional utilities

Note: The terminal feature can use `Snacks.nvim` or the native Neovim terminal. If `Snacks.nvim` is configured as the provider but is not available, it will fall back to the native terminal.

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ThomasK33/claudecode.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim", -- Added dependency
  },
  config = function()
    -- Ensure snacks is loaded if you want to use the terminal immediately
    -- require("snacks") -- Or handle this in your init.lua
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
  requires = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim", -- Added dependency
  },
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
      "folke/snacks.nvim", -- Added dependency
    },
    opts = {
      -- Optional configuration for claudecode main
      -- Example:
      -- terminal_cmd = "claude --magic-flag",

      -- Configuration for the interactive terminal can also be nested here:
      terminal = {
        split_side = "left",            -- "left" or "right"
        split_width_percentage = 0.4, -- 0.0 to 1.0
        provider = "snacks",          -- "snacks" or "native" (defaults to "snacks")
        show_native_term_exit_tip = true, -- Show tip for Ctrl-\\ Ctrl-N (defaults to true)
      },
    },
    -- The main require("claudecode").setup(opts) will handle passing
    -- opts.terminal to the terminal module's setup.
    config = true, -- or function(_, opts) require("claudecode").setup(opts) end
    keys = {
      { "<leader>cc", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Terminal" },
      { "<leader>ck", "<cmd>ClaudeCodeSend<cr>", desc = "Send to Claude Code" },
      { "<leader>co", "<cmd>ClaudeCodeOpen<cr>", desc = "Open Claude Terminal" },
      { "<leader>cx", "<cmd>ClaudeCodeClose<cr>", desc = "Close Claude Terminal" },
    },
  },
}
```

### Local Development with LazyVim

For local development with LazyVim, create a `lua/plugins/claudecode.lua` file with the following content:

```lua
return {
  {
    dir = "~/GitHub/claudecode.nvim",  -- Path to your local repository
    name = "claudecode.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim", -- Added dependency
    },
    dev = true,
    opts = {
      -- Development configuration for claudecode main
      log_level = "debug",
      auto_start = true,

      -- Example terminal configuration for dev:
      terminal = {
        split_side = "right",
        split_width_percentage = 0.25,
        provider = "native",
        show_native_term_exit_tip = false,
      },
    },
    config = true,
    keys = {
      { "<leader>cc", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Terminal" },
      { "<leader>ck", "<cmd>ClaudeCodeSend<cr>", desc = "Send to Claude Code" },
      { "<leader>co", "<cmd>ClaudeCodeOpen<cr>", desc = "Open Claude Terminal" },
      { "<leader>cx", "<cmd>ClaudeCodeClose<cr>", desc = "Close Claude Terminal" },
    },
  },
}
```

This configuration:

1. Uses the `dir` parameter to specify the local path to your repository
2. Sets `dev = true` to enable development mode
3. Sets a more verbose log level for debugging
4. Adds convenient keymaps for testing

## Configuration

```lua
require("claudecode").setup({
  -- Port range for WebSocket server (default: 10000-65535)
  port_range = { min = 10000, max = 65535 },

  -- Auto-start WebSocket server when the plugin is loaded.
  -- Note: With lazy-loading (e.g., LazyVim), this means the server starts when a plugin command is first used.
  auto_start = true,

  -- Custom terminal command to use when launching Claude
  -- This command is used by the new interactive terminal feature.
  -- If nil or empty, it defaults to "claude".
  terminal_cmd = nil, -- e.g., "my_claude_wrapper_script" or "claude --project-foo"

  -- Log level (trace, debug, info, warn, error)
  log_level = "info",

  -- Enable sending selection updates to Claude
  track_selection = true,

  -- Configuration for the interactive terminal (passed to claudecode.terminal.setup by the main setup function)
  terminal = {
    -- Side for the vertical split ('left' or 'right')
    split_side = "right", -- Default

    -- Width of the terminal as a percentage of total editor width (0.0 to 1.0)
    split_width_percentage = 0.30, -- Default

    -- Terminal provider ('snacks' or 'native')
    -- If 'snacks' is chosen but not available, it will fall back to 'native'.
    provider = "snacks", -- Default

    -- Whether to show a one-time tip about exiting native terminal mode (Ctrl-\\ Ctrl-N)
    show_native_term_exit_tip = true -- Default
  }
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
- `:ClaudeCode` - Toggle the Claude Code interactive terminal window
- `:ClaudeCodeOpen` - Open (or focus) the Claude Code terminal window
- `:ClaudeCodeClose` - Close the Claude Code terminal window

## Keymaps

No default keymaps are provided. Add your own in your configuration:

```lua
vim.keymap.set("n", "<leader>cc", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Terminal" })
vim.keymap.set({"n", "v"}, "<leader>ck", "<cmd>ClaudeCodeSend<cr>", { desc = "Send to Claude Code" })

-- Or more specific maps:
vim.keymap.set("n", "<leader>co", "<cmd>ClaudeCodeOpen<cr>", { desc = "Open Claude Terminal" })
vim.keymap.set("n", "<leader>cx", "<cmd>ClaudeCodeClose<cr>", { desc = "Close Claude Terminal" })
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
