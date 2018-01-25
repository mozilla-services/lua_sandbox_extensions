--[[
# Count-min Sketch implementation in Lua

Provides a probabilistic data structure to inform frequency calculation in an
event stream.

## Functions

### new

Create and return a new CMS data structure. Typical operations on this value will
involve calling the add and check functions.

*Arguments*
- epsilon (number) - CMS epsilon parameter
- delta (number) - CMS delta parameter

*Return*
- Returns initialized CMS structure
--]]

local math      = require("math")
local xxhash    = require("xxhash")
local hash      = xxhash.xxh32
local ostime    = require("os").time

local type          = type
local assert        = assert
local setmetatable  = setmetatable

local M = {}
setfenv(1, M)

math.randomseed(ostime())

function new(epsilon, delta)
  assert(type(epsilon) == "number", "epsilon must be a number")
  assert(epsilon > 0, "epsilon must be bigger than zero")
  assert(type(delta) == "number", "delta must be a number")
  assert(delta> 0, "delta must be bigger than zero")

  -- Count Min Sketch variables
  local w = math.ceil(2.718281828459045 / epsilon)
  local d = math.ceil(math.log(1 / delta))
  local l = d * w

  -- main datastructure
  local array = {}

  -- hash variables
  local seed1
  local seed2

  -- counter
  local addedItems
  local maxval = 2^53 - 1

  -- temporary index table
  local temp_index = {}
  for x = 1, d do
    temp_index[x] = 0
  end

  local query = function(input, update)
    assert(type(input) == "string", 'input must be a string')
    assert(type(update) == "boolean", 'update must be a boolean')

    -- make two different hash values from the input with different seeds
    local h1 = hash(input, seed1)
    local h2 = hash(input, seed2)

    -- track whether or not we have added a new value,  0 if added 1 if not added
    local existed = 1

    -- create hashes and compute array index and bit index for them to get
    -- the individual bits
    local min = maxval
    for i = 1, d do
      -- set offset, we are using one big array instead of many smaller ones
      local offset = (i - 1) * w

      -- use enhanced double hashing (Kirsh & Mitzenmacher) to create the hash
      -- value used for the array index. +1 to account for Lua arrays
      local x = ((h1 + (i * h2) + i^2) % w) + 1
      temp_index[i] = x
      local num = array[x + offset]

      -- if the bit is zero we know it did not exist already just return if we are
      -- not updating it
      if num == 0 then
        existed = 0
        if not update then
          return 0
        end
      end

      -- update the smallest seen value
      if num < min then
        min = num
      end
    end

    -- update the item counter if we added a new item
    if update then
      -- conservative update, only update values that smaller than min + 1
      for i = 1, d do
        local offset = (i - 1) * w
        local index = temp_index[i] + offset
        if array[index] < (min + 1) and min < maxval then
          array[index] = array[index] + 1
        end
      end

      -- update min in order to return the updated count
      min = min + 1

      -- update the items counter if we addded a new item
      if existed == 0 then
        addedItems = addedItems + 1
      end
    end

    return min
  end

  --[[
  Adds a new entry to the set. returns 1 if the element
  already existed and 0 if it does not exist in the set.
  ]]
  local add = function(input)
    return query(input, true)
  end

  --[[
  checks whether or not an element is in the set.
  returns 1 if the element exists and 0 if it does
  not exist in the set.
  ]]
  local check = function(input)
    return query(input, false)
  end

  --[[ resets the arrays used in the filter ]]
  local reset = function()
    addedItems = 0

    -- since 2*rand and 3*rand is done modulo a prime these number will always
    -- be different and should therefore safe to use as seeds to generate two
    -- different hashes for the same input.
    local rand = math.random(-2147483648, 2147483647)
    seed1 = (2*rand) % 2147483647
    seed2 = (3*rand) % 2147483647

    for x = 1, l do
      array[x] = 0
    end
  end

  -- [[ get number of unique added items ]]
  local getNumItems = function()
    return addedItems
  end

  -- [[ get number of bits this instance uses ]]
  local getDepth = function()
    return d
  end

  -- [[ get number of keys this instance uses ]]
  local getWidth = function()
    return w
  end

  -- [[ get number of keys this instance uses ]]
  local getAccumulatedError = function()
    return addedItems * epsilon
  end

  -- reset the array to initialize this instance
  reset()

  -- methods we expose for this instance
  local ret = {
    add = add,
    check = check,
    reset = reset,
    getNumItems = getNumItems,
    getDepth = getDepth,
    getWidth = getWidth,
    getAccumulatedError = getAccumulatedError
  }
  setmetatable(ret, {})
  return ret
end

return M
