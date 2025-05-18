# Claude Code Neovim Integration: Development Guide

This document provides an overview of the project structure, development workflow, and implementation priorities for contributors.

## Project Structure

```none
claudecode.nvim/
├── .github/workflows/       # CI workflow definitions
├── lua/claudecode/          # Plugin implementation
│   ├── server/              # WebSocket server implementation
│   ├── tools/               # MCP tool implementations
│   ├── config.lua           # Configuration management
│   ├── init.lua             # Plugin entry point
│   ├── lockfile.lua         # Lock file management
│   └── selection.lua        # Selection tracking
├── plugin/                  # Plugin loader
├── tests/                   # Test suite
│   ├── unit/                # Unit tests
│   ├── component/           # Component tests
│   ├── integration/         # Integration tests
│   └── mocks/               # Test mocks
├── README.md                # User documentation
├── ARCHITECTURE.md          # Architecture documentation
└── DEVELOPMENT.md           # Development guide
```

## Core Components Implementation Status

| Component              | Status         | Priority | Notes                              |
| ---------------------- | -------------- | -------- | ---------------------------------- |
| Basic plugin structure | ✅ Done        | -        | Initial setup complete             |
| Configuration system   | ✅ Done        | -        | Support for user configuration     |
| WebSocket server       | 🚧 Placeholder | High     | Need real implementation           |
| Lock file management   | ✅ Done        | -        | Basic implementation complete      |
| Selection tracking     | ✅ Done        | -        | Basic implementation complete      |
| MCP tools              | 🚧 Placeholder | High     | Need real implementation           |
| Tests                  | 🚧 Started     | High     | Framework set up, examples created |
| CI pipeline            | ✅ Done        | -        | GitHub Actions configured          |
| Documentation          | ✅ Done        | -        | Initial documentation complete     |

## Development Priorities

1. **WebSocket Server Implementation**

   - Implement real WebSocket server using lua-websockets
   - Add JSON-RPC 2.0 message handling
   - Add client connection management
   - Implement proper error handling

2. **MCP Tool Implementation**

   - Implement all required tools from the findings document
   - Map VS Code concepts to Neovim equivalents
   - Test each tool thoroughly

3. **Selection Tracking Enhancement**

   - Improve selection change detection
   - Ensure compatibility with various Neovim modes
   - Optimize performance with proper debouncing

4. **Integration Testing**
   - Develop comprehensive integration tests
   - Create mock Claude client for testing
   - Test edge cases and error handling

## Testing

Run tests using:

```bash
# Run all tests
cd claudecode.nvim
nvim --headless -u tests/minimal_init.lua -c "lua require('tests').run()"

# Run specific test file
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.unit.config_spec')"
```

## Implementation Guidelines

1. **Error Handling**

   - All public functions should have error handling
   - Return `success, result_or_error` pattern
   - Log meaningful error messages

2. **Performance**

   - Minimize impact on editor performance
   - Debounce event handlers
   - Use asynchronous operations where possible

3. **Compatibility**

   - Support Neovim >= 0.8.0
   - Minimize dependencies
   - Follow Neovim plugin best practices

4. **Testing**
   - Write tests before implementation (TDD)
   - Aim for high code coverage
   - Mock external dependencies

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement your changes with tests
4. Run the test suite to ensure all tests pass
5. Submit a pull request

## Implementation Details

### WebSocket Server

The WebSocket server should use either:

- [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket) library
- last resort, as unmaintained: [lua-websockets](https://github.com/lipp/lua-websockets)
  library
- Call out to a Node.js or Rust/Go server (if Lua implementation is problematic)

### Custom Tools

Custom tools beyond the basic VS Code implementation could include:

- Neovim-specific diagnostics
- LSP integration
- Telescope integration for file finding
- Git integration

## Next Steps

1. Implement the WebSocket server with real functionality
2. Complete the MCP tool implementations
3. Add more comprehensive tests
4. Create example configurations for popular Neovim setups
