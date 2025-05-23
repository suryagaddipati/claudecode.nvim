---@meta vim_api_definitions
-- This file provides type definitions for parts of the Neovim API
-- to help the Lua language server (LuaLS) with diagnostics.

---@class vim_log_levels
---@field NONE number
---@field ERROR number
---@field WARN number
---@field INFO number
---@field DEBUG number
---@field TRACE number

---@class vim_log
---@field levels vim_log_levels

---@class vim_notify_opts
---@field title string|nil
---@field icon string|nil
---@field on_open fun(winid: number)|nil
---@field on_close fun()|nil
---@field timeout number|nil
---@field keep fun()|nil
---@field plugin string|nil
---@field hide_from_history boolean|nil
---@field once boolean|nil
---@field on_close_timeout number|nil

---@class vim_options_table: table<string, any>

---@class vim_buffer_options_table: table<string, any>

---@class vim_bo_proxy: vim_buffer_options_table
---@operator #index(bufnr: number): vim_buffer_options_table Allows vim.bo[bufnr]

---@class vim_diagnostic_info
---@field bufnr number
---@field col number
---@field end_col number|nil
---@field end_lnum number|nil
---@field lnum number
---@field message string
---@field severity number
---@field source string|nil
---@field user_data any|nil

---@class vim_diagnostic_module
---@field get fun(bufnr?: number, ns_id?: number): vim_diagnostic_info[]
-- Add other vim.diagnostic functions as needed, e.g., get_namespace, set, etc.

---@class vim_global_api
---@field notify fun(msg: string | string[], level?: number, opts?: vim_notify_opts):nil
---@field log vim_log
---@field _last_echo table[]? table of tables, e.g. { {"message", "HighlightGroup"} }
---@field _last_error string?
---@field o vim_options_table For vim.o.option_name
---@field bo vim_bo_proxy      For vim.bo.option_name and vim.bo[bufnr].option_name
---@field diagnostic vim_diagnostic_module For vim.diagnostic.*
---@field empty_dict fun(): table For vim.empty_dict()
---@field schedule_wrap fun(fn: function): function For vim.schedule_wrap()
-- Add other vim object definitions here if they cause linting issues
-- e.g. vim.fn, vim.api, vim.loop, vim.deepcopy, etc.

---@class SpyCall
---@field vals table[] table of arguments passed to the call
---@field self any the 'self' object for the call if it was a method

---@class SpyInformation
---@field calls SpyCall[] A list of calls made to the spy.
---@field call_count number The number of times the spy has been called.
-- Add other spy properties if needed e.g. returned, threw

---@class SpyAsserts
---@field was_called fun(self: SpyAsserts, count?: number):boolean
---@field was_called_with fun(self: SpyAsserts, ...):boolean
---@field was_not_called fun(self: SpyAsserts):boolean
-- Add other spy asserts if needed

---@class SpyableFunction : function
---@field __call fun(self: SpyableFunction, ...):any
---@field spy fun(self: SpyableFunction):SpyAsserts Returns an assertion object for the spy.
---@field calls SpyInformation[]? Information about calls made to the spied function.
-- Note: In some spy libraries, 'calls' might be directly on the spied function,
-- or on an object returned by `spy()`. Adjust as per your spy library's specifics.
-- For busted's default spy, `calls` is often directly on the spied function.

-- This section helps LuaLS understand that 'vim' is a global variable
-- with the structure defined above. It's for type hinting only and
-- does not execute or overwrite the actual 'vim' global provided by Neovim.
---@type vim_global_api
