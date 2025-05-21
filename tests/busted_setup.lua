-- Test setup for busted

-- Create mock vim API if we're running tests outside of Neovim
if not _G.vim then
  _G.vim = require("tests.mocks.vim")
end

-- Ensure vim global is accessible
_G.vim = _G.vim or {}

-- Setup test globals
_G.assert = require("luassert")

-- Helper function to verify expectations
_G.expect = function(value)
  return {
    to_be = function(expected)
      assert.are.equal(expected, value)
    end,
    to_be_nil = function()
      assert.is_nil(value)
    end,
    to_be_true = function()
      assert.is_true(value)
    end,
    to_be_false = function()
      assert.is_false(value)
    end,
    to_be_table = function()
      assert.is_table(value)
    end,
    to_have_key = function(key)
      assert.is_table(value)
      assert.not_nil(value[key])
    end,
  }
end

-- Return true to indicate setup was successful
return true
