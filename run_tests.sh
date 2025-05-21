#!/bin/bash

# Set the correct Lua path to include project files
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"

# Run all tests
cd "$(dirname "$0")" || exit
echo "Running all tests..."

# Find all test files with consistent patterns
TEST_FILES=$(find tests -type f -name "*_test.lua" -o -name "*_spec.lua" | sort)
echo "Found test files:"
echo "$TEST_FILES"

if [ -n "$TEST_FILES" ]; then
  # Pass each test file individually to busted
  busted -v $TEST_FILES
else
  echo "No test files found"
fi
