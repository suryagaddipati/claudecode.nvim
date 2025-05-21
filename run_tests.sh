#!/bin/bash

# Set the correct Lua path to include project files
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$LUA_PATH"

cd "$(dirname "$0")" || exit
echo "Running all tests..."

TEST_FILES=$(find tests -type f -name "*_test.lua" -o -name "*_spec.lua" | sort)
echo "Found test files:"
echo "$TEST_FILES"

if [ -n "$TEST_FILES" ]; then
  # Pass test files to busted with coverage flag - quotes needed but shellcheck disabled as we need word splitting
  # shellcheck disable=SC2086
  busted --coverage -v $TEST_FILES
else
  echo "No test files found"
fi
