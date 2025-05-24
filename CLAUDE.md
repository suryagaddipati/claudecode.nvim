# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code Neovim Integration is a Neovim plugin that enables bidirectional communication between Neovim and the Claude Code CLI, allowing Claude to access file content, make edits, and respond to user selections within Neovim.

## Development Commands

```bash
# Format code with StyLua
make format

make check  # Runs luacheck
make test   # Runs all tests with busted
# Run specific test file
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.unit.config_spec')"
```

## Architecture

The plugin follows a modular architecture with these main components:

1. **WebSocket Server** (`lua/claudecode/server/init.lua`)

   - Handles communication with Claude Code CLI using JSON-RPC 2.0 protocol
   - Pure Lua implementation with RFC 6455 WebSocket compliance
   - Zero external dependencies

2. **Lock File System** (`lua/claudecode/lockfile.lua`)

   - Creates and manages lock files at `~/.claude/ide/[port].lock`
   - Enables Claude CLI to discover the Neovim integration

3. **MCP Tool System** (`lua/claudecode/tools/init.lua`)

   - Dynamic tool registration with schema validation
   - Implements openFile, openDiff, getCurrentSelection, getOpenEditors
   - Follows Model Context Protocol 2025-03-26 specification
   - Centralized tool definitions and automatic MCP exposure

4. **Diff Integration** (`lua/claudecode/diff.lua`)

   - Native Neovim diff support with configurable options
   - Current-tab mode (default) to reduce tab clutter
   - Helpful keymaps: `<leader>dq` (exit), `<leader>da` (accept all)
   - Automatic temporary file cleanup

5. **Selection Tracking** (`lua/claudecode/selection.lua`)

   - Monitors text selections and cursor position in Neovim
   - Sends updates to Claude via WebSocket

6. **Terminal Integration** (`lua/claudecode/terminal.lua`)

   - Supports both Snacks.nvim and native Neovim terminals
   - Vertical split terminal with configurable positioning
   - Commands: `:ClaudeCode`, `:ClaudeCodeOpen`, `:ClaudeCodeClose`

7. **Configuration** (`lua/claudecode/config.lua`)

   - Handles user configuration validation and merging with defaults
   - Includes diff provider and terminal configuration

8. **Main Plugin Entry** (`lua/claudecode/init.lua`)
   - Exposes setup and control functions
   - Manages plugin lifecycle

## Development Status

The plugin is in beta stage with:

- Core structure and configuration system implemented
- Complete WebSocket server with RFC 6455 compliance
- Enhanced selection tracking with multi-mode support
- Lock file management implemented
- Complete MCP tool framework with dynamic registration
- Core MCP tools: openFile, openDiff, getCurrentSelection, getOpenEditors
- Native Neovim diff integration with configurable options
- Terminal integration (Snacks.nvim and native support)
- Comprehensive test suite (55+ tests passing)

## Testing Approach

The project uses the Busted testing framework:

- Unit tests for individual modules
- Mock implementations for external dependencies
- Test files organized into unit and component tests
- Prioritize test-driven development (TDD)
- Tests MUST fail for unimplemented features, never skip tests with TODOs
- Each placeholder or future implementation must have corresponding failing tests
- Run tests frequently to validate code changes

## Development Priorities

Current priorities for development are:

1. Implementing diffview.nvim integration for the diff provider system
2. Adding Neovim-specific tools (LSP integration, diagnostics, Telescope)
3. Performance optimization for large codebases
4. Integration testing with real Claude Code CLI

## Development Principles

- Implement in idiomatic Lua
- Prioritize correctness over quick implementations
- Write minimal, focused code without unnecessary complexity
- Avoid cutting corners or implementing quick hacks
- Follow Neovim plugin best practices
- Create modular code with clear separation of concerns
- Follow error-first return patterns (success, error_message)
- Implement proper error handling with descriptive messages

## Dependencies & Requirements

- Neovim >= 0.8.0
- **Zero external dependencies** - Pure Lua implementation
- Development tools:
  - LuaCheck for linting
  - StyLua for formatting
  - Busted for testing

## Documentation Requirements

- Document LazyVim integration in README.md
- Include clear local development instructions
- Provide comprehensive installation guides
- Document proper repository structure for coder/claudecode.nvim

## User Commands

The plugin provides these user-facing commands:

- `:ClaudeCode` - Toggle the Claude Code interactive terminal
- `:ClaudeCodeOpen` - Open/focus the Claude Code terminal
- `:ClaudeCodeClose` - Close the Claude Code terminal
- `:ClaudeCodeSend` - Send current selection to Claude as at-mentioned context
- `:ClaudeCodeStatus` - Show connection status (via Lua API)

## Debugging

Set the log level to debug for more detailed information:

```lua
require("claudecode").setup({
  log_level = "debug",
})
```

## Configuration Options

```lua
{
  -- Port range for WebSocket server (default: 10000-65535)
  port_range = { min = 10000, max = 65535 },

  -- Auto-start WebSocket server on Neovim startup
  auto_start = true,

  -- Custom terminal command to use when launching Claude
  terminal_cmd = nil, -- e.g., "claude --project-foo"

  -- Log level (trace, debug, info, warn, error)
  log_level = "info",

  -- Enable sending selection updates to Claude
  track_selection = true,

  -- Diff provider configuration for openDiff MCP tool
  diff_provider = "auto", -- "auto", "native", or "diffview"
  diff_opts = {
    auto_close_on_accept = true,    -- Auto-close diff when accepting changes
    show_diff_stats = true,         -- Show diff statistics
    vertical_split = true,          -- Use vertical split for diff view
    open_in_current_tab = true,     -- Open diff in current tab (reduces clutter)
  },

  -- Terminal configuration
  terminal = {
    split_side = "right",           -- "left" or "right"
    split_width_percentage = 0.30,  -- 0.0 to 1.0
    provider = "snacks",            -- "snacks" or "native"
    show_native_term_exit_tip = true, -- Show tip for Ctrl-\\ Ctrl-N
  },
}
```
