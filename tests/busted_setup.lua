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
    to_be_string = function()
      assert.is_string(value)
    end,
    to_be_function = function()
      assert.is_function(value)
    end,
    to_be_boolean = function()
      assert.is_boolean(value)
    end,
    to_be_at_least = function(expected)
      assert.is_true(value >= expected)
    end,
    to_have_key = function(key)
      assert.is_table(value)
      assert.not_nil(value[key])
    end,
    to_contain = function(expected)
      if type(value) == "string" then
        assert.is_true(string.find(value, expected, 1, true) ~= nil)
      elseif type(value) == "table" then
        local found = false
        for _, v in ipairs(value) do
          if v == expected then
            found = true
            break
          end
        end
        assert.is_true(found)
      else
        error("to_contain can only be used with strings or tables")
      end
    end,
    not_to_be_nil = function()
      assert.is_not_nil(value)
    end,
    not_to_contain = function(expected)
      if type(value) == "string" then
        assert.is_true(string.find(value, expected, 1, true) == nil)
      elseif type(value) == "table" then
        local found = false
        for _, v in ipairs(value) do
          if v == expected then
            found = true
            break
          end
        end
        assert.is_false(found)
      else
        error("not_to_contain can only be used with strings or tables")
      end
    end,
    to_be_truthy = function()
      assert.is_truthy(value)
    end,
  }
end

-- Return true to indicate setup was successful
return true
