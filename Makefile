.PHONY: check format test clean

# Default target
all: check format

# Check for syntax errors
check:
	@echo "Checking Lua files for syntax errors..."
	@find lua -name "*.lua" -type f -exec lua -e "assert(loadfile('{}'))" \;
	@echo "Running luacheck..."
	@luacheck lua/ --no-unused-args --no-max-line-length || echo "⚠️  Luacheck warnings - continuing anyway"

# Format all files
format:
	@echo "Formatting files..."
	@if command -v nix >/dev/null 2>&1; then \
		nix fmt; \
	elif command -v stylua >/dev/null 2>&1; then \
		stylua lua/; \
	else \
		echo "Neither nix nor stylua found. Please install one of them."; \
		exit 1; \
	fi

# Run tests
test:
	@echo "Running tests..."
	@./run_tests.sh

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -f luacov.report.out luacov.stats.out
	@rm -f tests/lcov.info

# Print available commands
help:
	@echo "Available commands:"
	@echo "  make check  - Check for syntax errors"
	@echo "  make format - Format all files (uses nix fmt or stylua)"
	@echo "  make test   - Run tests"
	@echo "  make clean  - Clean generated files"
	@echo "  make help   - Print this help message"
