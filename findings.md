# Claude Code Integration: Analysis Findings

## Overview

This document outlines the findings from analyzing the Claude Code VS Code extension to understand how to implement a similar integration for Neovim. It provides detailed technical information for developers looking to create compatible implementations for other editors.

## Communication Protocol

- The extension uses WebSockets for bidirectional communication with the Claude CLI
- It implements the Model Context Protocol (MCP) - referenced in the repository URL (`https://github.com/anthropic-labs/vscode-mcp`) and package dependencies
- The extension starts an HTTP server that hosts a WebSocket server for the Claude CLI to connect to
- JSON-RPC 2.0 style messaging is used for communication between the extension and CLI
- The WebSocket server is created using the `ws` npm package
- The protocol follows a specific lifecycle (initialization, operation, shutdown) as described in the MCP 2025-03-26 specification
- Proper initialization is required before any tool operations can be performed

### Message Format

All messages follow the JSON-RPC 2.0 format with the following structure:

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": {
    /* method-specific parameters */
  }
}
```

## Environment Integration

- Sets environment variables in the terminal where Claude runs:
  - `CLAUDE_CODE_SSE_PORT`: The port number where the WebSocket server is listening
  - `ENABLE_IDE_INTEGRATION`: Set to "true" to activate IDE integration features
- Creates lock files in `~/.claude/ide/[port].lock` containing:
  - Current workspace information (folder paths)
  - Process ID
  - IDE name
  - Transport method ("ws" for WebSocket)

### Lock File Format

The lock file contains a JSON object with the following structure:

```json
{
  "pid": 12345, // Process ID of the IDE
  "workspaceFolders": ["/path/to/workspace"], // Open workspace folders
  "ideName": "VS Code", // Name of the IDE
  "transport": "ws" // Transport method (WebSocket)
}
```

## Editor Integration

- Tracks text selection changes in the editor and sends them to Claude
- Provides tools to the CLI for file operations:
  - Opening files
  - Showing diffs between files
  - Getting workspace information
  - Executing code in Jupyter notebooks
  - Managing tabs
- Registers VS Code commands for launching Claude and sending selections

## Key Implementation Details

- Uses a WebSocket server on a random available port (10000-65535)
- Writes lock files with workspace and IDE info for Claude CLI to discover
- The lock file path follows the pattern: `~/.claude/ide/[port].lock`
- Creates in-memory file systems for handling diffs
- Monitors selection changes in the editor to provide context to Claude
- Implements the Model Context Protocol (MCP) server with tool registration
- Updates the lock file when workspace folders change

## Message Types

### Messages From Claude Code to VS Code Extension

1. **Tool Invocation Requests**:

   Based on the MCP 2025-03-26 specification, the correct format should be:

   ```json
   {
     "jsonrpc": "2.0",
     "id": "request-123",
     "method": "tools/call",
     "params": {
       "name": "toolName",
       "arguments": {
         /* tool-specific parameters matching the inputSchema */
       }
     }
   }
   ```

   Tool parameters are defined in the response to the `tools/list` method:

   ```json
   {
     "jsonrpc": "2.0",
     "id": "tools-list-request",
     "result": {
       "tools": [
         {
           "name": "toolName",
           "description": "Tool description",
           "inputSchema": {
             "type": "object",
             "properties": {
               "paramName": {
                 "type": "string",
                 "description": "Parameter description"
               }
             },
             "required": ["paramName"],
             "additionalProperties": false,
             "$schema": "http://json-schema.org/draft-07/schema#"
           }
         }
       ]
     }
   }
   ```

   **Note**: Our testing shows that the current VSCode extension doesn't actually respond to these tool calls. The extension currently only sends notifications to Claude rather than receiving commands. However, the Neovim implementation should still support these methods for future compatibility.

2. **Connection Initialization**:

   The MCP lifecycle requires a proper initialization sequence:

   ```json
   {
     "jsonrpc": "2.0",
     "id": "init-1",
     "method": "initialize",
     "params": {
       "protocolVersion": "2025-03-26",
       "capabilities": {
         "roots": { "listChanged": true },
         "sampling": {}
       },
       "clientInfo": {
         "name": "ClientName",
         "version": "1.0.0"
       }
     }
   }
   ```

   Followed by an initialized notification (two formats appear in the spec, both should be supported):

   ```json
   {
     "jsonrpc": "2.0",
     "method": "initialized"
   }
   ```

   Or:

   ```json
   {
     "jsonrpc": "2.0",
     "method": "notifications/initialized"
   }
   ```

   **Note**: Our testing shows the VSCode extension doesn't respond to initialization messages with the expected response. However, the Neovim implementation should still implement the full MCP lifecycle for future compatibility.

### Messages From VS Code Extension to Claude Code

1. **Selection Updates**:

   Testing confirms this is the primary message type actually sent by the extension.

   ```json
   {
     "jsonrpc": "2.0",
     "method": "selection_changed",
     "params": {
       "text": "selected text",
       "filePath": "/path/to/file",
       "fileUrl": "file:///path/to/file",
       "selection": {
         "start": { "line": 0, "character": 0 },
         "end": { "line": 0, "character": 0 },
         "isEmpty": false
       }
     }
   }
   ```

   Neovim must send these notifications when selection changes occur to keep Claude informed of the current context.

2. **At-Mention Notifications**:

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

3. **Event Logging**:

   ```json
   {
     "jsonrpc": "2.0",
     "method": "log_event",
     "params": {
       "eventName": "event_name",
       "eventData": {}
     }
   }
   ```

4. **Tool Response Messages**:

   ```json
   {
     "jsonrpc": "2.0",
     "id": "request_id",
     "result": {
       "content": [{ "type": "text", "text": "response text" }]
     }
   }
   ```

## MCP Tools Implemented

The extension registers various tools with the MCP server:

1. **openDiff**: Open a diff view between two files and wait for user action

   - Parameters:
     - `old_file_path`: Path to the original file (REQUIRED)
     - `new_file_path`: Path to the new file (REQUIRED)
     - `new_file_contents`: Contents of the new file (REQUIRED)
     - `tab_name`: Name for the diff tab (REQUIRED)
   - Behavior: This tool is **blocking** - it opens the diff view and waits for user interaction before returning
   - Returns: One of three possible responses based on user action:

     ```json
     // User saved the file (accepted changes)
     {
       "content": [
         { "type": "text", "text": "FILE_SAVED" },
         { "type": "text", "text": "final file contents" }
       ]
     }

     // User closed the diff tab or explicitly rejected
     {
       "content": [
         { "type": "text", "text": "DIFF_REJECTED" },
         { "type": "text", "text": "tab_name" }
       ]
     }
     ```

   - Implementation Notes:
     - Creates temporary file providers for both old and new files
     - Monitors for tab close events, file save events, and diff acceptance/rejection
     - Automatically closes any existing Claude Code diff tabs with the same name
     - Uses `Promise.race()` to wait for the first of: tab closed, diff accepted, or file saved
     - If autoSave is disabled, also waits for manual save events

2. **getDiagnostics**: Get language diagnostics from VS Code

   - Parameters: None
   - Returns: List of diagnostics (errors, warnings) in open files

3. **close_tab**: Close a tab by name

   - Parameters:
     - `tab_name`: Name of the tab to close (REQUIRED)
   - Returns: Status message

4. **openFile**: Open a file in the editor and optionally select text

   - Parameters:
     - `filePath`: Path to the file to open (REQUIRED)
     - `preview`: Whether to open in preview mode (default: false)
     - `startText`: Text pattern to find for start of selection (REQUIRED)
     - `endText`: Text pattern to find for end of selection (REQUIRED)
     - `selectToEndOfLine`: Whether to select to end of line containing match
   - Returns: Status message

5. **getOpenEditors**: Get information about open editors

   - Parameters: None
   - Returns: List of open editors with file paths and metadata

6. **getWorkspaceFolders**: Get all workspace folders currently open

   - Parameters: None
   - Returns: List of workspace folders with paths and metadata

7. **getCurrentSelection**: Get current text selection in active editor

   - Parameters: None
   - Returns: Selected text with location information

8. **checkDocumentDirty**: Check if a document has unsaved changes

   - Parameters:
     - `filePath`: Path to the file to check (REQUIRED)
   - Returns: Boolean indicating whether the document is dirty

9. **saveDocument**: Save a document with unsaved changes

   - Parameters:
     - `filePath`: Path to the file to save (REQUIRED)
   - Returns: Status message

10. **getLatestSelection**: Get the most recent text selection

    - Parameters: None
    - Returns: Most recent selection with location information

11. **executeCode**: Execute Python code in Jupyter kernel
    - Parameters:
      - `code`: The code to execute (REQUIRED)
    - Returns: Execution results and/or output

## Implementation Strategy for Neovim

To implement this functionality in Neovim:

1. **WebSocket Server**:

   - Create a WebSocket server implementing the MCP protocol (2025-03-26 or compatible version)
   - Use a library like `lua-websockets` or integrate with a Node.js server
   - Implement JSON-RPC 2.0 message handling
   - Follow the proper MCP lifecycle (initialize, initialized notification, then operations)
   - Note that currently the VSCode extension appears primarily to send notifications to Claude rather than receive commands
   - Implement the full MCP protocol for future compatibility even if current tools aren't invoked

2. **Lock File Management**:

   - Generate lock files in `~/.claude/ide/[port].lock` with the required structure
   - Update lock files when workspace folders change
   - Clean up lock files when the plugin is disabled

3. **Environment Variable Management**:

   - Set `CLAUDE_CODE_SSE_PORT` and `ENABLE_IDE_INTEGRATION` when launching Claude
   - Create a terminal buffer for Claude or modify the user's terminal environment

4. **Selection Tracking**:

   - Monitor visual selections and cursor movements in Neovim
   - Send selection updates to Claude via WebSocket
   - Implement at-mention detection for sending file contexts

5. **Tool Implementation**:

   - Implement each MCP tool using Neovim's API
   - Create helper functions for common operations
   - Map VS Code concepts to Neovim equivalents (tabs, diagnostics, etc.)

6. **User Commands**:

   - Create Neovim commands for launching Claude
   - Add key mappings for common operations
   - Provide configuration options for customization

7. **Error Handling**:
   - Implement robust error handling for WebSocket communication
   - Provide user feedback for connection issues
   - Log errors for debugging purposes

The most critical components are the lock file system and WebSocket server that the Claude CLI uses to discover and communicate with the IDE integration.
