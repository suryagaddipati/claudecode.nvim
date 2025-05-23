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

| Component              | Status     | Priority | Notes                                    |
| ---------------------- | ---------- | -------- | ---------------------------------------- |
| Basic plugin structure | ✅ Done    | -        | Initial setup complete                   |
| Configuration system   | ✅ Done    | -        | Support for user configuration           |
| WebSocket server       | ✅ Done    | -        | Pure Lua RFC 6455 compliant              |
| Lock file management   | ✅ Done    | -        | Basic implementation complete            |
| Selection tracking     | ✅ Done    | -        | Enhanced with multi-mode support         |
| MCP tools              | 🚧 Started | Medium   | Basic framework, need more tools         |
| Tests                  | ✅ Done    | -        | 56 tests passing, comprehensive coverage |
| CI pipeline            | ✅ Done    | -        | GitHub Actions configured                |
| Documentation          | ✅ Done    | -        | Complete documentation                   |

## Development Priorities

1. **MCP Tool Enhancement**

   - Implement additional tools from the findings document
   - Add Neovim-specific tools (LSP, diagnostics, Telescope integration)
   - Enhance existing tool implementations

2. **Performance Optimization**

   - Monitor WebSocket server performance under load
   - Optimize selection tracking for large files
   - Fine-tune debouncing and event handling

3. **User Experience**

   - Add more user commands and keybindings
   - Improve error messages and user feedback
   - Create example configurations for popular setups

4. **Integration Testing**
   - Test with real Claude Code CLI
   - Validate compatibility across Neovim versions
   - Create end-to-end test scenarios

## Testing

Run tests using:

```bash
# Run all tests
make test

# Run specific test file
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.unit.config_spec')"

# Run linting
make check

# Format code
make format
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
   - Zero external dependencies (pure Lua implementation)
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

The WebSocket server is implemented in pure Lua with zero external dependencies:

- **Pure Neovim Implementation**: Uses `vim.loop` (libuv) for TCP operations
- **RFC 6455 Compliant**: Full WebSocket protocol implementation
- **JSON-RPC 2.0**: MCP message handling with proper framing
- **Security**: Pure Lua SHA-1 implementation for WebSocket handshake
- **Performance**: Optimized with lookup tables and efficient algorithms

### Custom Tools

Custom tools beyond the basic VS Code implementation could include:

- Neovim-specific diagnostics
- LSP integration
- Telescope integration for file finding
- Git integration

## Next Steps

1. Enhance MCP tool implementations with Neovim-specific features
2. Add integration tests with real Claude Code CLI
3. Optimize performance for large codebases
4. Create example configurations for popular Neovim setups (LazyVim, NvChad, etc.)
