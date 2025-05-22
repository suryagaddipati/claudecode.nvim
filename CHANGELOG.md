# Changelog

All notable changes to the Claude Code Neovim Integration will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project structure and core modules
- **Complete WebSocket server implementation using pure Neovim built-ins**
  - RFC 6455 compliant WebSocket protocol implementation
  - JSON-RPC 2.0 message handling for MCP protocol
  - Zero external dependencies (uses vim.loop, vim.json, vim.schedule)
  - Support for multiple concurrent client connections
  - Ping/pong keepalive and graceful connection management
  - Full HTTP upgrade handshake with proper WebSocket accept key generation
  - WebSocket frame encoding/decoding with masking support
- Lock file management for Claude CLI discovery
- Selection tracking for editor context
- MCP tool implementations
- Basic commands (:ClaudeCodeStart, :ClaudeCodeStop, :ClaudeCodeStatus, :ClaudeCodeSend)
- Automatic shutdown and cleanup on Neovim exit
- Testing framework with Busted (55 tests passing)
- Development environment with Nix flakes
- Comprehensive luacheck linting with zero warnings

### Changed

## [0.1.0-alpha] - TBD

- Initial alpha release
