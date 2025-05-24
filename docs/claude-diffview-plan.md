# Claude Code Neovim: Configurable Diff Provider Implementation Plan

## Overview

This document outlines the implementation plan for adding a configurable diff provider system to the Claude Code Neovim plugin. The system will support both native Neovim diff capabilities and enhanced functionality through the diffview.nvim plugin, with automatic detection and graceful fallbacks.

## Background

The Claude Code integration requires an `openDiff` MCP (Model Context Protocol) tool that can display differences between two files. This tool needs to:

- Display diffs between an original file and new content provided by Claude
- Support custom tab naming for better organization
- Provide a user-friendly interface for reviewing and accepting changes
- Work reliably across different Neovim configurations

## Architecture Design

### Provider System

Following the established pattern from the terminal provider implementation, the diff system will support three provider modes:

1. **`auto`** (default): Automatically detects diffview.nvim availability and uses it if present, otherwise falls back to native diff
2. **`diffview`**: Explicitly uses diffview.nvim (warns if not available and falls back to native)
3. **`native`**: Uses only native Neovim diff capabilities

### Configuration Schema

The configuration will be added to the main plugin configuration:

```lua
require("claudecode").setup({
  -- Existing configuration...

  -- NEW: Diff provider configuration
  diff_provider = "auto", -- "auto", "diffview", "native"
  diff_opts = {
    auto_close_on_accept = true,
    show_diff_stats = true,
    vertical_split = true,
    open_in_current_tab = true, -- Use current tab instead of creating new tab
  },
})
```

## Implementation Plan

### Phase 1: Configuration Updates

#### File: `lua/claudecode/config.lua`

**Add to defaults:**

```lua
M.defaults = {
  -- ... existing defaults ...
  diff_provider = "auto",
  diff_opts = {
    auto_close_on_accept = true,
    show_diff_stats = true,
    vertical_split = true,
  },
}
```

**Add validation:**

```lua
function M.validate(config)
  -- ... existing validations ...

  -- Validate diff_provider
  local valid_diff_providers = { "auto", "diffview", "native" }
  local is_valid_diff_provider = false
  for _, provider in ipairs(valid_diff_providers) do
    if config.diff_provider == provider then
      is_valid_diff_provider = true
      break
    end
  end
  assert(is_valid_diff_provider, "diff_provider must be one of: " .. table.concat(valid_diff_providers, ", "))

  -- Validate diff_opts
  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  assert(type(config.diff_opts.auto_close_on_accept) == "boolean", "diff_opts.auto_close_on_accept must be a boolean")
  assert(type(config.diff_opts.show_diff_stats) == "boolean", "diff_opts.show_diff_stats must be a boolean")
  assert(type(config.diff_opts.vertical_split) == "boolean", "diff_opts.vertical_split must be a boolean")

  return true
end
```

### Phase 2: Diff Provider Module

#### File: `lua/claudecode/diff.lua` (NEW)

Create a dedicated diff provider module that:

1. **Detects diffview.nvim availability** using `pcall(require, "diffview")`
2. **Provides provider selection logic** following the terminal provider pattern
3. **Implements native diff functionality** using Neovim's built-in diff mode
4. **Implements diffview.nvim integration** for enhanced diff experience
5. **Handles temporary file management** with proper cleanup
6. **Provides consistent API** regardless of provider used

Key functions:

- `M.setup(user_diff_config)` - Configure the diff module
- `M.open_diff(old_file_path, new_file_path, new_file_contents, tab_name)` - Main diff opening function
- `M.get_current_provider()` - Returns the effective provider being used
- `M.is_diffview_available()` - Checks diffview.nvim availability

### Phase 3: Native Diff Implementation

The native diff implementation will:

1. **Create temporary files** for new content with proper naming
2. **Use Neovim's diff mode** (`vim.cmd("diffthis")`)
3. **Configure split layout** (vertical/horizontal based on configuration)
4. **Set up buffer properties** (nofile, bufhidden=wipe, custom naming)
5. **Implement cleanup** using autocommands for buffer/window events
6. **Provide diff statistics** when enabled

### Phase 4: Diffview.nvim Integration

The diffview.nvim integration will:

1. **Leverage diffview's API** for creating custom diff views
2. **Use enhanced UI features** like file panels and navigation
3. **Support Git integration** when applicable
4. **Provide better merge conflict resolution** tools
5. **Maintain compatibility** with diffview's workflow

### Phase 5: Tool Integration

#### File: `lua/claudecode/tools/init.lua`

**Fix parameter handling:**

```lua
function M.handle_invoke(_, params)
  local tool_name = params.name
  local input = params.arguments  -- Changed from params.input to match MCP 2025-03-26
  -- ... rest unchanged
end
```

**Update openDiff implementation:**

```lua
function M.open_diff(params)
  -- Enhanced parameter validation
  local required_params = {"old_file_path", "new_file_path", "new_file_contents", "tab_name"}
  for _, param in ipairs(required_params) do
    if not params[param] then
      return {
        type = "text",
        text = "Error: Missing required parameter: " .. param,
        isError = true
      }
    end
  end

  -- Use the diff module
  local diff = require("claudecode.diff")

  local success, result = pcall(function()
    return diff.open_diff(
      params.old_file_path,
      params.new_file_path,
      params.new_file_contents,
      params.tab_name
    )
  end)

  if not success then
    return {
      type = "text",
      text = "Error opening diff: " .. tostring(result),
      isError = true
    }
  end

  return {
    type = "text",
    text = string.format(
      "Diff opened using %s provider: %s (%s vs %s)",
      result.provider,
      result.tab_name,
      params.old_file_path,
      params.new_file_path
    )
  }
end
```

### Phase 6: MCP Protocol Updates

#### File: `lua/claudecode/server/init.lua`

**Update tools/list handler:**

```lua
["tools/list"] = function(client, params)
  return {
    tools = {
      {
        name = "openDiff",
        description = "Open a diff view between two files",
        inputSchema = {
          type = "object",
          properties = {
            old_file_path = {
              type = "string",
              description = "Path to the original file"
            },
            new_file_path = {
              type = "string",
              description = "Path to the new file"
            },
            new_file_contents = {
              type = "string",
              description = "Contents of the new file"
            },
            tab_name = {
              type = "string",
              description = "Name for the diff tab"
            }
          },
          required = {"old_file_path", "new_file_path", "new_file_contents", "tab_name"},
          additionalProperties = false,
          ["$schema"] = "http://json-schema.org/draft-07/schema#"
        }
      },
      -- ... other tools
    }
  }
end,
```

## Technical Specifications

### MCP Tool Parameters

Based on findings.md, the openDiff tool must accept:

- `old_file_path`: Path to the original file (REQUIRED)
- `new_file_path`: Path to the new file (REQUIRED)
- `new_file_contents`: Contents of the new file (REQUIRED)
- `tab_name`: Name for the diff tab (REQUIRED)

### Native Diff Features

Native implementation provides:

- **Zero dependencies** - Works with any Neovim installation
- **Standard diff operations** - `dp` (diffput), `do` (diffget), `]c`/`[c` navigation
- **Configurable layout** - Vertical or horizontal splits
- **Proper cleanup** - Automatic temporary file removal
- **Buffer management** - Custom naming and scratch buffer configuration

### Diffview.nvim Features

Enhanced implementation provides:

- **Rich UI** - File panels, commit history, merge tools
- **Git integration** - Native VCS support and conflict resolution
- **Advanced navigation** - Cycle through multiple files, jump between hunks
- **Professional workflow** - Single tabpage interface for complex diffs

### Error Handling

The implementation includes robust error handling for:

1. **File permissions** - Check write access for temporary directories
2. **Large files** - Handle memory constraints for large content
3. **Binary files** - Detect and handle binary content appropriately
4. **Cleanup failures** - Ensure temporary files are removed on errors
5. **Provider failures** - Graceful fallback between providers
6. **Buffer conflicts** - Handle name collisions with existing buffers

## Testing Strategy

### Unit Tests

Required tests include:

1. **Configuration validation** - Test all config options and validation rules
2. **Provider detection** - Test auto-detection and fallback logic
3. **Parameter validation** - Test all required parameter combinations
4. **File operations** - Test temporary file creation and cleanup
5. **Error scenarios** - Test all error conditions and edge cases

### Integration Tests

Required integration tests:

1. **End-to-end workflow** - Full openDiff tool invocation
2. **Provider switching** - Test switching between providers
3. **Multiple concurrent diffs** - Test resource management
4. **Cleanup verification** - Test memory and file cleanup
5. **Configuration changes** - Test runtime configuration updates

## Migration and Compatibility

### Backward Compatibility

- Existing configurations continue to work unchanged
- New diff configuration is optional with sensible defaults
- No breaking changes to existing functionality

### Migration Path

1. **Immediate**: Plugin works with native diff out of the box
2. **Optional**: Users can install diffview.nvim for enhanced experience
3. **Configurable**: Users can explicitly choose their preferred provider

## Documentation Updates

### Configuration Documentation

Update README.md to include:

- New diff provider configuration options
- Examples of different provider configurations
- Benefits of each provider type
- Installation instructions for optional dependencies

### Usage Examples

Provide examples for:

```lua
-- Auto-detect (recommended)
require("claudecode").setup({
  diff_provider = "auto",
})

-- Force diffview.nvim (warns if not available)
require("claudecode").setup({
  diff_provider = "diffview",
})

-- Use only native diff
require("claudecode").setup({
  diff_provider = "native",
  diff_opts = {
    vertical_split = false, -- Use horizontal splits
    show_diff_stats = false, -- Disable statistics
  },
})
```

## Implementation Timeline

1. **Phase 1-2**: Configuration and diff module (~2-3 days)
2. **Phase 3**: Native diff implementation (~2-3 days)
3. **Phase 4**: Diffview.nvim integration (~3-4 days)
4. **Phase 5-6**: Tool and protocol updates (~1-2 days)
5. **Testing and documentation**: (~2-3 days)

**Total estimated time**: ~10-15 days

## Success Criteria

The implementation will be considered successful when:

1. ✅ **Zero-dependency operation** - Works with native Neovim diff
2. ✅ **Enhanced experience** - Utilizes diffview.nvim when available
3. ✅ **Automatic detection** - Seamlessly chooses best available provider
4. ✅ **MCP compliance** - Implements exact openDiff specification
5. ✅ **Robust error handling** - Graceful failures and cleanup
6. ✅ **User configurable** - Flexible provider and behavior options
7. ✅ **Well tested** - Comprehensive test coverage
8. ✅ **Documented** - Clear usage examples and configuration guide

This implementation will provide Claude Code users with a powerful, flexible diff system that enhances their code review workflow while maintaining the plugin's zero-dependency principle.
