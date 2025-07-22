--- Integration between gitsigns and ClaudeCode
-- Provides functions to send git hunks to Claude via the selection system
-- @module claudecode.gitsigns_integration

local M = {}

local logger = require("claudecode.logger")

--- Check if gitsigns is available
-- @return boolean, table|nil Whether gitsigns is available and the gitsigns module if available
local function check_gitsigns_available()
  local ok, gitsigns = pcall(require, "gitsigns")
  return ok, gitsigns
end

--- Get the git hunk at the current cursor position
-- @return table|nil The hunk data if found, nil otherwise
local function get_current_hunk()
  local available, gitsigns = check_gitsigns_available()
  if not available then
    logger.warn("gitsigns_integration", "gitsigns.nvim not available")
    return nil
  end

  -- Get current buffer
  local buf = vim.api.nvim_get_current_buf()

  -- Check if gitsigns is attached to this buffer
  if not vim.b[buf].gitsigns_head then
    logger.warn("gitsigns_integration", "gitsigns not attached to current buffer")
    return nil
  end

  -- Use the modern gitsigns API to get hunk at cursor
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Try gitsigns.get_hunks() with buffer parameter
  local hunks = nil
  local ok1, result = pcall(gitsigns.get_hunks, buf)
  if ok1 and result then
    hunks = result
  else
    -- Try without buffer parameter (older API)
    local ok2, result2 = pcall(gitsigns.get_hunks)
    if ok2 and result2 then
      hunks = result2
    end
  end

  if not hunks or #hunks == 0 then
    return nil
  end

  -- Find hunk containing cursor
  for _, hunk in ipairs(hunks) do
    -- Handle different hunk format versions
    local start_line = hunk.start or hunk.added and hunk.added.start or hunk.removed and hunk.removed.start
    local count = hunk.count or hunk.added and hunk.added.count or hunk.removed and hunk.removed.count or 1

    if start_line and cursor_line >= start_line and cursor_line <= (start_line + count - 1) then
      return hunk
    end
  end

  return nil
end

--- Get hunk content as git diff format
-- @param hunk table The hunk data from gitsigns
-- @return string The formatted git diff hunk
local function format_hunk_content(hunk)
  local buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(buf)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  local relative_path = vim.fn.fnamemodify(file_path, ":.")

  -- Primary method: Use gitsigns structured data
  if hunk.lines and hunk.head and hunk.added and hunk.removed then
    local formatted = string.format("Git Diff Hunk in %s:\n\n", file_name)
    formatted = formatted .. "```diff\n"

    -- Add diff header (file paths)
    formatted = formatted .. string.format("--- a/%s\n", relative_path)
    formatted = formatted .. string.format("+++ b/%s\n", relative_path)

    -- Add hunk header from gitsigns
    formatted = formatted .. hunk.head .. "\n"

    -- Add all diff lines from gitsigns structured data
    for _, line in ipairs(hunk.lines) do
      formatted = formatted .. line .. "\n"
    end

    formatted = formatted .. "```\n"

    -- Add context information
    local head = vim.b[buf].gitsigns_head
    if head and head ~= "" then
      formatted = formatted .. "\nComparing against: " .. head
    end

    -- Add hunk type and line information
    local hunk_type = hunk.type or "change"
    formatted = formatted .. string.format("\nHunk type: %s (removed: %d lines, added: %d lines)",
      hunk_type, hunk.removed.count or 0, hunk.added.count or 0)

    return formatted
  end

  -- Fallback 1: Use partial gitsigns data with reconstructed diff
  if hunk.lines then
    -- Handle different hunk format versions for line numbers
    local start_line = hunk.start or hunk.added and hunk.added.start or hunk.removed and hunk.removed.start
    local count = hunk.count or hunk.added and hunk.added.count or hunk.removed and hunk.removed.count or 1

    if not start_line then
      return "Git Hunk in " .. file_name .. " (format not recognized)"
    end

    local formatted = string.format("Git Diff Hunk in %s:\n\n", file_name)
    formatted = formatted .. "```diff\n"

    -- Add basic diff header
    formatted = formatted .. string.format("--- a/%s\n", relative_path)
    formatted = formatted .. string.format("+++ b/%s\n", relative_path)

    -- Reconstruct hunk header if not available
    local removed_count = hunk.removed and hunk.removed.count or count
    local added_count = hunk.added and hunk.added.count or count
    local removed_start = hunk.removed and hunk.removed.start or start_line
    local added_start = hunk.added and hunk.added.start or start_line

    formatted = formatted .. string.format("@@ -%d,%d +%d,%d @@\n",
      removed_start, removed_count, added_start, added_count)

    -- Add diff lines
    for _, line in ipairs(hunk.lines) do
      formatted = formatted .. line .. "\n"
    end

    formatted = formatted .. "```\n"

    -- Add context
    local head = vim.b[buf].gitsigns_head
    if head and head ~= "" then
      formatted = formatted .. "\nComparing against: " .. head
    end

    return formatted
  end

  -- Fallback 2: Git command parsing (only if gitsigns data unavailable)
  logger.warn("gitsigns_integration", "Gitsigns structured data not available, falling back to git command")

  local start_line = hunk.start or hunk.added and hunk.added.start or hunk.removed and hunk.removed.start
  local count = hunk.count or hunk.added and hunk.added.count or hunk.removed and hunk.removed.count or 1

  if not start_line then
    return "Git Hunk in " .. file_name .. " (format not recognized)"
  end

  local git_diff_cmd = string.format("git diff HEAD -- %s", vim.fn.shellescape(relative_path))
  local diff_output = vim.fn.system(git_diff_cmd)

  if vim.v.shell_error == 0 and diff_output ~= "" then
    local diff_lines = vim.split(diff_output, "\n")
    local hunk_diff_lines = {}
    local in_target_hunk = false
    local target_hunk_found = false

    for _, line in ipairs(diff_lines) do
      -- Look for hunk headers
      if line:match("^@@") then
        local _, _, new_start, new_count = line:match("@@%s%-(%d+),?(%d*)%s%+(%d+),?(%d*)%s@@")
        new_start = tonumber(new_start)
        new_count = tonumber(new_count) or 1

        -- Check if this is our target hunk using proper range calculation
        if new_start and new_start <= start_line and (new_start + new_count - 1) >= start_line then
          in_target_hunk = true
          target_hunk_found = true
          table.insert(hunk_diff_lines, line)
        else
          in_target_hunk = false
        end
      elseif in_target_hunk then
        -- Include all lines that are part of the diff (not just +/- prefixed)
        if line:match("^[+%-]") or line:match("^ ") or line:match("^\\") then
          table.insert(hunk_diff_lines, line)
        elseif line:match("^@@") then
          -- Hit next hunk, stop
          break
        elseif line == "" then
          -- Include empty lines within hunks
          table.insert(hunk_diff_lines, line)
        end
      end
    end

    if target_hunk_found and #hunk_diff_lines > 0 then
      local formatted = string.format("Git Diff Hunk in %s:\n\n", file_name)
      formatted = formatted .. "```diff\n"

      -- Add diff header from original output
      for _, line in ipairs(diff_lines) do
        if line:match("^---") or line:match("^%+%+%+") then
          formatted = formatted .. line .. "\n"
        elseif line:match("^@@") then
          break
        end
      end

      -- Add the hunk
      formatted = formatted .. table.concat(hunk_diff_lines, "\n") .. "\n"
      formatted = formatted .. "```\n"

      -- Add context
      local head = vim.b[buf].gitsigns_head
      if head and head ~= "" then
        formatted = formatted .. "\nComparing against: " .. head
      end

      return formatted
    end
  end

  -- Final fallback: Basic hunk information
  return string.format("Git Hunk in %s (lines %d-%d) - Unable to retrieve diff content",
    file_name, start_line, start_line + count - 1)
end

--- Send current git hunk to Claude via visual selection
-- This method selects the hunk text and lets ClaudeCode's selection system pick it up
function M.send_current_hunk_via_selection()
  local hunk = get_current_hunk()
  if not hunk then
    vim.notify("No git hunk found at cursor position", vim.log.levels.WARN)
    return false
  end

  -- Handle different hunk format versions
  local start_line = hunk.start or hunk.added and hunk.added.start or hunk.removed and hunk.removed.start
  local count = hunk.count or hunk.added and hunk.added.count or hunk.removed and hunk.removed.count or 1

  if not start_line then
    vim.notify("Cannot determine hunk location", vim.log.levels.ERROR)
    return false
  end

  logger.debug("gitsigns_integration", "Selecting hunk at lines", start_line, "to", start_line + count - 1)

  -- Move cursor to start of hunk
  vim.api.nvim_win_set_cursor(0, {start_line, 0})

  -- Enter visual line mode and select the hunk
  vim.cmd("normal! V")
  if count > 1 then
    vim.cmd("normal! " .. (count - 1) .. "j")
  end

  vim.notify("Git hunk selected - it will be sent to Claude", vim.log.levels.INFO)
  return true
end

--- Send current git hunk to Claude via the selection system directly
-- This method bypasses visual selection and sends the hunk data directly
function M.send_current_hunk_direct()
  local selection_module = require("claudecode.selection")

  if not selection_module.state.tracking_enabled or not selection_module.server then
    vim.notify("ClaudeCode is not running", vim.log.levels.ERROR)
    return false
  end

  local hunk = get_current_hunk()
  if not hunk then
    vim.notify("No git hunk found at cursor position", vim.log.levels.WARN)
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(buf)

  -- Format the hunk content
  local hunk_content = format_hunk_content(hunk)

  -- Handle different hunk format versions for selection data
  local start_line = hunk.start or hunk.added and hunk.added.start or hunk.removed and hunk.removed.start
  local count = hunk.count or hunk.added and hunk.added.count or hunk.removed and hunk.removed.count or 1

  -- Create selection data similar to ClaudeCode's format
  local selection_data = {
    text = hunk_content,
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = start_line - 1, character = 0 },
      ["end"] = { line = start_line + count - 2, character = 0 },
      isEmpty = false
    }
  }

  logger.debug("gitsigns_integration", "Sending hunk directly to Claude:", selection_data)

  -- Send via ClaudeCode's selection system
  selection_module.send_selection_update(selection_data)

  vim.notify("Git hunk sent to Claude: " .. vim.fn.fnamemodify(file_path, ":t") ..
    " (lines " .. start_line .. "-" .. (start_line + count - 1) .. ")", vim.log.levels.INFO)
  return true
end

--- Send all hunks in current buffer to Claude
function M.send_all_hunks()
  local available, gitsigns = check_gitsigns_available()
  if not available then
    vim.notify("gitsigns.nvim not available", vim.log.levels.ERROR)
    return false
  end

  local selection_module = require("claudecode.selection")

  if not selection_module.state.tracking_enabled or not selection_module.server then
    vim.notify("ClaudeCode is not running", vim.log.levels.ERROR)
    return false
  end

  -- Get current buffer and check gitsigns attachment
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].gitsigns_head then
    vim.notify("gitsigns not attached to current buffer", vim.log.levels.WARN)
    return false
  end

  -- Try to get all hunks using gitsigns API
  local hunks = nil
  local ok1, result = pcall(gitsigns.get_hunks, buf)
  if ok1 and result then
    hunks = result
  else
    -- Try without buffer parameter (older API)
    local ok2, result2 = pcall(gitsigns.get_hunks)
    if ok2 and result2 then
      hunks = result2
    end
  end

  if not hunks or #hunks == 0 then
    vim.notify("No git hunks found in current buffer", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(current_buf)
  local file_name = vim.fn.fnamemodify(file_path, ":t")
  local relative_path = vim.fn.fnamemodify(file_path, ":.")

  -- Get the complete git diff for this file
  local git_diff_cmd = string.format("git diff HEAD -- %s", vim.fn.shellescape(relative_path))
  local diff_output = vim.fn.system(git_diff_cmd)

  local all_hunks_text
  if vim.v.shell_error == 0 and diff_output ~= "" then
    -- Use the actual git diff output
    all_hunks_text = string.format("Complete Git Diff for %s:\n\n", file_name)
    all_hunks_text = all_hunks_text .. "```diff\n"
    all_hunks_text = all_hunks_text .. diff_output
    all_hunks_text = all_hunks_text .. "```\n"

    -- Add context
    local head = vim.b[current_buf].gitsigns_head
    if head and head ~= "" then
      all_hunks_text = all_hunks_text .. "\nComparing against: " .. head
    end
  else
    -- Fallback: combine individual hunk formats
    all_hunks_text = "All Git Hunks in " .. file_name .. ":\n\n"

    for i, hunk in ipairs(hunks) do
      local hunk_content = format_hunk_content(hunk)
      all_hunks_text = all_hunks_text .. string.format("Hunk %d:\n", i)
      all_hunks_text = all_hunks_text .. hunk_content .. "\n\n"
    end
  end

  -- Create selection data
  local selection_data = {
    text = all_hunks_text,
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = 0, character = 0 },
      ["end"] = { line = vim.api.nvim_buf_line_count(current_buf) - 1, character = 0 },
      isEmpty = false
    }
  }

  selection_module.send_selection_update(selection_data)

  vim.notify("All " .. #hunks .. " git hunks sent to Claude from " .. file_name, vim.log.levels.INFO)
  return true
end

--- Setup function to create user commands and keybindings
-- @param opts table|nil Configuration options
-- @field opts.create_commands boolean Create user commands (default: true)
-- @field opts.create_keymaps boolean Create default keymaps (default: false)
-- @field opts.keymaps table Custom keymap definitions
function M.setup(opts)
  opts = opts or {}

  if opts.create_commands ~= false then
    -- Create user commands
    vim.api.nvim_create_user_command("ClaudeCodeSendHunk", function()
      M.send_current_hunk_direct()
    end, {
      desc = "Send current git hunk to Claude"
    })

    vim.api.nvim_create_user_command("ClaudeCodeSendHunkVis", function()
      M.send_current_hunk_via_selection()
    end, {
      desc = "Send current git hunk to Claude via visual selection"
    })

    vim.api.nvim_create_user_command("ClaudeCodeSendAllHunks", function()
      M.send_all_hunks()
    end, {
      desc = "Send all git hunks in current buffer to Claude"
    })
  end

  if opts.create_keymaps then
    local keymaps = opts.keymaps or {
      send_hunk = "<leader>ch",
      send_hunk_visual = "<leader>cv",
      send_all_hunks = "<leader>ca",
    }

    vim.keymap.set('n', keymaps.send_hunk, M.send_current_hunk_direct,
      { desc = 'Send current git hunk to Claude' })
    vim.keymap.set('n', keymaps.send_hunk_visual, M.send_current_hunk_via_selection,
      { desc = 'Send current git hunk to Claude (visual)' })
    vim.keymap.set('n', keymaps.send_all_hunks, M.send_all_hunks,
      { desc = 'Send all git hunks to Claude' })
  end
end

return M