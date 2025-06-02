# How Claude Code IDE Extensions Actually Work

This document explains the protocol and architecture behind Claude Code's IDE integrations, based on reverse-engineering the VS Code extension. Use this guide to build your own integrations or understand how the official ones work.

## TL;DR

Claude Code extensions create WebSocket servers in your IDE that Claude connects to. They use a WebSocket variant of MCP (Model Context Protocol) that only Claude supports. The IDE writes a lock file with connection info, sets some environment variables, and Claude automatically connects when launched.

## How Discovery Works

When you launch Claude Code from your IDE, here's what happens:

### 1. IDE Creates a WebSocket Server

The extension starts a WebSocket server on a random port (10000-65535) that listens for connections from Claude.

### 2. Lock File Creation

The IDE writes a discovery file to `~/.claude/ide/[port].lock`:

```json
{
  "pid": 12345, // IDE process ID
  "workspaceFolders": ["/path/to/project"], // Open folders
  "ideName": "VS Code", // or "Neovim", "IntelliJ", etc.
  "transport": "ws" // WebSocket transport
}
```

### 3. Environment Variables

When launching Claude, the IDE sets:

- `CLAUDE_CODE_SSE_PORT`: The WebSocket server port
- `ENABLE_IDE_INTEGRATION`: Set to "true"

### 4. Claude Connects

Claude reads the lock files, finds the matching port from the environment, and connects to the WebSocket server.

## The Protocol

Communication uses WebSocket with JSON-RPC 2.0 messages:

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": {
    /* parameters */
  },
  "id": "unique-id" // for requests that expect responses
}
```

The protocol is based on MCP (Model Context Protocol) specification 2025-03-26, but uses WebSocket transport instead of stdio/HTTP.

## Key Message Types

### From IDE to Claude

These are notifications the IDE sends to keep Claude informed:

#### 1. Selection Updates

Sent whenever the user's selection changes:

```json
{
  "jsonrpc": "2.0",
  "method": "selection_changed",
  "params": {
    "text": "selected text content",
    "filePath": "/absolute/path/to/file.js",
    "fileUrl": "file:///absolute/path/to/file.js",
    "selection": {
      "start": { "line": 10, "character": 5 },
      "end": { "line": 15, "character": 20 },
      "isEmpty": false
    }
  }
}
```

#### 2. At-Mentions

When the user explicitly sends a selection as context:

```json
{
  "jsonrpc": "2.0",
  "method": "at_mentioned",
  "params": {
    "filePath": "/path/to/file",
    "lineStart": 10,
    "lineEnd": 20
  }
}
```

### From Claude to IDE

According to the MCP spec, Claude should be able to call tools, but **current implementations are mostly one-way** (IDE → Claude).

#### Tool Calls (Future)

```json
{
  "jsonrpc": "2.0",
  "id": "request-123",
  "method": "tools/call",
  "params": {
    "name": "openFile",
    "arguments": {
      "filePath": "/path/to/file.js"
    }
  }
}
```

#### Tool Responses

```json
{
  "jsonrpc": "2.0",
  "id": "request-123",
  "result": {
    "content": [{ "type": "text", "text": "File opened successfully" }]
  }
}
```

## Available MCP Tools

The extensions register these tools that Claude can (theoretically) call:

### Core Tools

1. **openFile** - Open a file and optionally select text

   ```json
   {
     "filePath": "/path/to/file.js",
     "startText": "function hello", // Find and select from this text
     "endText": "}" // To this text
   }
   ```

2. **openDiff** - Show a diff and wait for user action (blocking!)

   ```json
   {
     "old_file_path": "/path/to/original.js",
     "new_file_path": "/path/to/modified.js",
     "new_file_contents": "// Modified content...",
     "tab_name": "Proposed changes"
   }
   ```

   Returns `FILE_SAVED` or `DIFF_REJECTED` based on user action.

3. **getCurrentSelection** - Get the current text selection
4. **getOpenEditors** - List all open files
5. **getWorkspaceFolders** - Get project folders
6. **getDiagnostics** - Get errors/warnings from the IDE
7. **saveDocument** - Save a file
8. **close_tab** - Close a tab by name (note the inconsistent naming!)

### Implementation Notes

- Most tools follow camelCase naming except `close_tab` (uses snake_case)
- The `openDiff` tool is unique - it's **blocking** and waits for user interaction
- Tools return MCP-formatted responses with content arrays
- There's also `executeCode` for Jupyter notebooks in the VS Code extension

## Building Your Own Integration

Here's the minimum viable implementation:

### 1. Create a WebSocket Server

```lua
-- Listen on localhost only (important!)
local server = create_websocket_server("127.0.0.1", random_port)
```

### 2. Write the Lock File

```lua
-- ~/.claude/ide/[port].lock
local lock_data = {
  pid = vim.fn.getpid(),
  workspaceFolders = { vim.fn.getcwd() },
  ideName = "YourEditor",
  transport = "ws"
}
write_json(lock_path, lock_data)
```

### 3. Set Environment Variables

```bash
export CLAUDE_CODE_SSE_PORT=12345
export ENABLE_IDE_INTEGRATION=true
claude  # Claude will now connect!
```

### 4. Handle Messages

```lua
-- Send selection updates
send_message({
  jsonrpc = "2.0",
  method = "selection_changed",
  params = { ... }
})

-- Implement tools (if needed)
register_tool("openFile", function(params)
  -- Open file logic
  return { content = {{ type = "text", text = "Done" }} }
end)
```

## Security Considerations

**Always bind to localhost (`127.0.0.1`) only!** This ensures the WebSocket server is not exposed to the network.

## What's Next?

With this protocol knowledge, you can:

- Build integrations for any editor
- Create agents that connect to existing IDE extensions
- Extend the protocol with custom tools
- Build bridges between different AI assistants and IDEs

The WebSocket MCP variant is currently Claude-specific, but the concepts could be adapted for other AI coding assistants.

## Resources

- [MCP Specification](https://spec.modelcontextprotocol.io)
- [Claude Code Neovim Implementation](https://github.com/coder/claudecode.nvim)
- [Official VS Code Extension](https://github.com/anthropic-labs/vscode-mcp) (minified source)
