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
   - Currently uses placeholder implementations

2. **Lock File System** (`lua/claudecode/lockfile.lua`)

   - Creates and manages lock files at `~/.claude/ide/[port].lock`
   - Enables Claude CLI to discover the Neovim integration

3. **Selection Tracking** (`lua/claudecode/selection.lua`)

   - Monitors text selections and cursor position in Neovim
   - Sends updates to Claude via WebSocket

4. **Configuration** (`lua/claudecode/config.lua`)

   - Handles user configuration validation and merging with defaults

5. **Main Plugin Entry** (`lua/claudecode/init.lua`)
   - Exposes setup and control functions
   - Manages plugin lifecycle

## Development Status

The plugin is in alpha stage with:

- Core structure and configuration system implemented
- Basic lock file management implemented
- Selection tracking implemented
- WebSocket server and MCP tool implementation still using placeholders

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

1. Implementing a real WebSocket server with lua-websockets or similar
2. Implementing MCP tools for file operations and editor features
3. Enhancing selection tracking
4. Adding comprehensive integration tests

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
- Lua >= 5.1
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

- `:ClaudeCodeStart` - Start the Claude Code integration
- `:ClaudeCodeStop` - Stop the integration
- `:ClaudeCodeStatus` - Show connection status
- `:ClaudeCodeSend` - Send current selection to Claude

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
  terminal_cmd = nil, -- e.g., "toggleterm"

  -- Log level (trace, debug, info, warn, error)
  log_level = "info",

  -- Enable sending selection updates to Claude
  track_selection = true,
}
```
