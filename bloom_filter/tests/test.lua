-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "bloom_filter"
assert(bloom_filter.version() == "1.0.0", bloom_filter.version())

local errors = {
    function() local bf = bloom_filter.new(2) end, -- new() incorrect # args
    function() local bf = bloom_filter.new(nil, 0.01) end, -- new() non numeric item
    function() local bf = bloom_filter.new(0, 0.01) end, -- invalid items
    function() local bf = bloom_filter.new(2, nil) end, -- nil probability
    function() local bf = bloom_filter.new(2, 0) end, -- invalid probability
    function() local bf = bloom_filter.new(2, 1) end, -- invalid probability
    function()
        local bf = bloom_filter.new(20, 0.01)
        bf:add() --incorrect # args
    end,
    function()
        local bf = bloom_filter.new(20, 0.01)
        bf:add({}) --incorrect argument type
    end,
    function()
        local bf = bloom_filter.new(20, 0.01)
        bf:query() --incorrect # args
    end,
    function()
        local bf = bloom_filter.new(20, 0.01)
        bf:query({}) --incorrect argument type
    end,
    function()
        local bf = bloom_filter.new(20, 0.01)
        bf:clear(1) --incorrect # args
    end,
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

bf = bloom_filter.new(1000, 0.01)
local test_items = 950

-- test numbers
assert(bf:count() == 0, "bloom filter should be empty")
assert(not bf:query(1), "bloom filter should be empty")
for i=1, test_items do
    assert(bf:add(i), "insert failed")
end
for i=1, test_items do
    assert(bf:query(i), "query failed")
end
assert(bf:count() == test_items, "count=" .. bf:count())
bf:clear()
assert(bf:count() == 0, "bloom filter should be empty")
assert(not bf:query(1), "bloom filter should be empty")

-- test strings
for i=1, test_items do
    assert(bf:add(tostring(i)), "insert failed")
end
for i=1, test_items do
    assert(bf:query(tostring(i)), "query failed")
end
assert(bf:count() == test_items, "count=" .. bf:count())
bf:clear()
assert(bf:count() == 0, "bloom filter should be empty")
assert(not bf:query("1"), "bloom filter should be empty")
