# Claude Code Neovim Integration: Architecture

This document describes the architecture of the Claude Code Neovim integration plugin.

## Overview

The plugin establishes a bidirectional communication channel between Neovim and the Claude Code CLI using WebSockets and the Model Context Protocol (MCP). This allows Claude to interact with Neovim, accessing file content, making edits, and responding to user selections.

## Core Components

### 1. WebSocket Server

The WebSocket server is the communication backbone of the plugin, implemented using pure Neovim built-ins:

- **Pure Neovim Implementation**: Uses `vim.loop` (libuv) for TCP server operations
- **RFC 6455 Compliant**: Full WebSocket protocol implementation
- **JSON-RPC 2.0**: Standard message format for MCP communication
- **Zero Dependencies**: No external libraries required
- **Async Processing**: Non-blocking operations integrated with Neovim's event loop
- **Multiple Clients**: Supports concurrent WebSocket connections
- **Connection Management**: Ping/pong keepalive and graceful disconnection

```
┌─────────────┐                  ┌─────────────┐
│             │   WebSocket/     │             │
│  Neovim     │◄──► JSON-RPC 2.0 │  Claude CLI │
│  Plugin     │                  │             │
└─────────────┘                  └─────────────┘
```

**WebSocket Server Architecture:**

```
┌─────────────────┐
│   TCP Server    │ ◄─── vim.loop.new_tcp()
│  (vim.loop)     │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ HTTP Upgrade    │ ◄─── WebSocket handshake
│   Handler       │
└─────────┬───────┘
          │
┌─────────▼───────┐
│ WebSocket Frame │ ◄─── RFC 6455 frame processing
│   Parser        │
└─────────┬───────┘
          │
┌─────────▼───────┐
│   JSON-RPC      │ ◄─── MCP message routing
│  Message Router │
└─────────────────┘
```

### 2. Lock File System

The lock file system enables Claude CLI to discover the Neovim integration:

- Creates lock files at `~/.claude/ide/[port].lock`
- Contains workspace folders, PID, and transport information
- Updated when workspace folders change
- Removed when the plugin is disabled or Neovim exits

```json
{
  "pid": 12345,
  "workspaceFolders": ["/path/to/workspace"],
  "ideName": "Neovim",
  "transport": "ws"
}
```

### 3. MCP Tool Implementation

The plugin implements tools that Claude can invoke:

- File operations (open, save, check status)
- Editor information (diagnostics, open editors)
- Selection management
- Diff viewing

Each tool follows a request/response pattern:

```
Claude CLI                            Neovim Plugin
    │                                      │
    │ ─────Tool Request (JSON-RPC)───────► │
    │                                      │
    │                                      │ ┌─────────────┐
    │                                      │ │ Execute     │
    │                                      │ │ tool logic  │
    │                                      │ └─────────────┘
    │                                      │
    │ ◄────Tool Response (JSON-RPC)─────── │
    │                                      │
```

### 4. Selection Tracking

The plugin monitors text selections in Neovim:

- Uses autocommands to detect selection changes
- Debounces updates to avoid flooding Claude
- Formats selection data according to MCP protocol
- Sends updates to Claude via WebSocket
- Supports sending `at_mentioned` notifications for visual selections using the `:ClaudeCodeSend` command, providing focused context to Claude.

### 5. Terminal Integration

The plugin provides a dedicated terminal interface for Claude Code CLI:

- Uses [folke/snacks.nvim](https://github.com/folke/snacks.nvim) for terminal management
- Creates a vertical split terminal with customizable size and position
- Supports focus, toggle, and close operations
- Maintains terminal state across operations
- Automatically cleans up on window close

```
┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
│             │    │                 │    │             │
│  Neovim     │◄───┤ Claude Terminal │◄───┤  Claude CLI │
│  Buffers    │    │ (Snacks.nvim)   │    │             │
└─────────────┘    └─────────────────┘    └─────────────┘
```

### 6. Environment Integration

The plugin manages the environment for Claude CLI:

- Sets required environment variables:
  - `CLAUDE_CODE_SSE_PORT`: The WebSocket server port
  - `ENABLE_IDE_INTEGRATION`: Enabled flag
- Provides configuration for the terminal command

## Message Flow

1. **Initialization:**

   ```
   Neovim Plugin ──► Start WebSocket Server
                  ──► Create Lock File
                  ──► Set Up Autocommands
   ```

2. **Claude Connection:**

   ```
   Claude CLI     ──► Read Lock File
                  ──► Connect to WebSocket
                  ──► Send Handshake
   Neovim Plugin  ──► Accept Connection
                  ──► Process Handshake
   ```

3. **Tool Invocation:**

   ```
   Claude CLI     ──► Send Tool Request
   Neovim Plugin  ──► Process Request
                  ──► Execute Tool Logic
                  ──► Send Response
   ```

4. **Selection Updates:**

   ```
   User           ──► Make Selection in Neovim
   Neovim Plugin  ──► Detect Selection Change
                  ──► Format Selection Data
                  ──► Send Update to Claude (e.g., `selection_changed` or `at_mentioned` via `:ClaudeCodeSend`)
   ```

## Module Structure

```
lua/claudecode/
├── init.lua              # Main entry point and setup
├── config.lua            # Configuration management
├── server/
│   ├── init.lua          # WebSocket server main interface with JSON-RPC 2.0
│   ├── tcp.lua           # TCP server using vim.loop
│   ├── utils.lua         # Utility functions (base64, SHA-1, HTTP parsing)
│   ├── frame.lua         # WebSocket frame encoding/decoding (RFC 6455)
│   ├── handshake.lua     # HTTP upgrade and WebSocket handshake
│   ├── client.lua        # WebSocket client connection management
│   └── mock.lua          # Mock server for testing
├── lockfile.lua          # Lock file management
├── tools/
│   └── init.lua          # Tool registration and dispatch
├── selection.lua         # Selection tracking and notifications
├── terminal.lua          # Terminal management (Snacks.nvim or native)
└── meta/
    └── vim.lua           # Vim API type definitions
```

**WebSocket Server Implementation Details:**

- **`server/tcp.lua`**: Creates TCP server using `vim.loop.new_tcp()`, handles port binding and client connections
- **`server/handshake.lua`**: Processes HTTP upgrade requests, validates WebSocket headers, generates accept keys
- **`server/frame.lua`**: Implements WebSocket frame parsing/encoding per RFC 6455 specification
- **`server/client.lua`**: Manages individual WebSocket client connections and state
- **`server/utils.lua`**: Provides base64 encoding, SHA-1 hashing, and XOR operations in pure Lua
- **`server/init.lua`**: Main server interface that orchestrates all components and handles JSON-RPC messages

## Testing Architecture

The testing strategy involves multiple layers:

1. **Unit Tests:**

   - Test individual functions in isolation
   - Mock dependencies as needed

2. **Component Tests:**

   - Test subsystems (WebSocket, tools, etc.)
   - Use controlled environment

3. **Integration Tests:**
   - Test end-to-end functionality
   - Use mock Claude client

Tests are organized parallel to the module structure:

```
tests/
├── unit/
│   ├── config_spec.lua
│   ├── server_spec.lua
│   ├── terminal_spec.lua
│   └── tools_spec.lua
├── component/
│   ├── server_spec.lua
│   └── tools_spec.lua
├── integration/
│   └── e2e_spec.lua
├── mocks/
│   ├── neovim.lua
│   └── claude_client.lua
└── harness.lua
```

## Security Considerations

- The WebSocket server only accepts local connections
- Lock files contain no sensitive information
- File operations only work within workspace folders
- No credentials or tokens are stored or transmitted

## Performance Considerations

- Selection tracking is debounced to reduce overhead
- File operations are asynchronous where possible
- The plugin maintains minimal memory footprint
- Idle resource usage is negligible
