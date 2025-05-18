#!/bin/bash

# Set the correct Lua path to include project files
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"

# Run all tests
cd "$(dirname "$0")" || exit
echo "Running all tests..."
busted -v tests/simple_test.lua tests/config_test.lua tests/server_test.lua tests/selection_test.lua

