# Claude Code Neovim Integration: Architecture

This document describes the architecture of the Claude Code Neovim integration plugin.

## Overview

The plugin establishes a bidirectional communication channel between Neovim and the Claude Code CLI using WebSockets and the Model Context Protocol (MCP). This allows Claude to interact with Neovim, accessing file content, making edits, and responding to user selections.

## Core Components

### 1. WebSocket Server

The WebSocket server is the communication backbone of the plugin:

- Implements JSON-RPC 2.0 message format
- Listens on a dynamically selected port (10000-65535)
- Handles client connections from Claude Code CLI
- Dispatches incoming requests to appropriate handlers

```
┌─────────────┐                  ┌─────────────┐
│             │   WebSocket/     │             │
│  Neovim     │◄──► JSON-RPC 2.0 │  Claude CLI │
│  Plugin     │                  │             │
└─────────────┘                  └─────────────┘
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

### 5. Environment Integration

The plugin manages the environment for Claude CLI:

- Sets required environment variables:
  - `CLAUDE_CODE_SSE_PORT`: The WebSocket server port
  - `ENABLE_IDE_INTEGRATION`: Enabled flag
- Provides terminal integration for launching Claude

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
                  ──► Send Update to Claude
   ```

## Module Structure

```
lua/claudecode/
├── init.lua              # Main entry point and setup
├── config.lua            # Configuration management
├── server/
│   ├── init.lua          # WebSocket server initialization
│   ├── message.lua       # Message formatting and parsing
│   └── handler.lua       # Request handlers
├── lockfile.lua          # Lock file management
├── tools/
│   ├── init.lua          # Tool registration
│   ├── file.lua          # File operation tools
│   ├── editor.lua        # Editor information tools
│   └── selection.lua     # Selection management tools
├── selection.lua         # Selection tracking
├── environment.lua       # Environment variable management
└── util.lua              # Utility functions
```

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
