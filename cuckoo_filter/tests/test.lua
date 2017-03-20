-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cuckoo_filter"
assert(cuckoo_filter.version() == "1.1.1", cuckoo_filter.version())

local errors = {
    function() local cf = cuckoo_filter.new(2, 99) end, -- new() incorrect # args
    function() local cf = cuckoo_filter.new(nil) end, -- new() non numeric item
    function() local cf = cuckoo_filter.new(0) end, -- invalid items
    function()
        local cf = cuckoo_filter.new(20)
        cf:add() --incorrect # args
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:add({}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:query() --incorrect # args
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:query({}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:clear(1) --incorrect # args
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:fromstring({}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter.new(20)
        cf:fromstring("                       ") --incorrect argument length
    end,
    function()
        local cf = cuckoo_filter.new(2) -- must specify atleast 4 items
    end
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

cf = cuckoo_filter.new(1000000)
local test_items = 800000


-- test numbers
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query(1), "cuckoo filter should be empty")
cf:clear()
for i=1, test_items do
    local added = cf:add(i)
end
assert(cf:count() == 799977, "count=" .. cf:count())

for i=1, test_items do
    assert(cf:query(i), "query failed " .. i .. " " .. cf:count())
end

local dcnt = 0
for i=1, test_items do
   if cf:delete(i) then
       dcnt = dcnt + 1
   end
end
assert(dcnt == 799977, "deleted count=" .. dcnt)
assert(cf:count() == 0, "count=" .. cf:count())

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query(1), "cuckoo filter should be empty")

-- test strings
for i=1, test_items do
    cf:add(tostring(i))
end
assert(cf:count() == 799967, "count=" .. cf:count()) -- lower accuracy is expected since the string only use 0-9

for i=1, test_items do
    assert(cf:query(tostring(i)), "query failed")
end
assert(cf:delete("500000"))
assert(cf:count() == 799966, "count=" .. cf:count())

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query("1"), "cuckoo filter should be empty")

cf = cuckoo_filter.new(8)
for i=1, 8 do
    local ok, err = pcall(cf.add, cf, 8)
    if not ok then
        assert(i == 8, tostring(i))
    end
end


require "cuckoo_filter_expire"
assert(cuckoo_filter_expire.version() == "1.1.1", cuckoo_filter_expire.version())

local errors = {
    function() local cf = cuckoo_filter_expire.new(1024, 1, 3) end, -- new() incorrect # args
    function() local cf = cuckoo_filter_expire.new(nil, 1) end, -- new() non numeric item
    function() local cf = cuckoo_filter_expire.new(0) end, -- invalid items
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:add() --incorrect # args
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:add("foo") --incorrect # args
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:add("foo", {}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:query() --incorrect # args
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:query({}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:clear(1) --incorrect # args
    end,
    function()
        local cf = cuckoo_filter_expire.new(1024)
        cf:fromstring({}) --incorrect argument type
    end,
    function()
        local cf = cuckoo_filter_expire.new(20)
        cf:fromstring("                       ") --incorrect argument length
    end,
    function()
        local cf = cuckoo_filter_expire.new(2) -- must specify atleast 4 items
    end
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

cf = cuckoo_filter_expire.new(1000000, 1)

-- test numbers
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query(1), "cuckoo filter should be empty")
cf:clear()
for i=1, test_items do
   cf:add(i, 1)
end
assert(cf:count() == 800000, "count=" .. cf:count())

for i=1, test_items do
    assert(cf:query(i), "query failed " .. i .. " " .. cf:count())
end

local dcnt = 0
for i=1, test_items do
   if cf:delete(i) then
       dcnt = dcnt + 1
   end
end
assert(dcnt == test_items, "deleted count=" .. dcnt)
assert(cf:count() == 0, "count=" .. cf:count())

cf:add(1, 260 * 60) -- expire everything by time

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query(1), "cuckoo filter should be empty")

-- test strings
for i=1, test_items do
    cf:add(tostring(i), 1)
end
assert(cf:count() == test_items, "count=" .. cf:count()) -- lower acuracy is expected since the string only use 0-9

for i=1, test_items do
    assert(cf:query(tostring(i)), "query failed")
end
assert(cf:delete("500000"))
assert(cf:count() == test_items - 1, "count=" .. cf:count())

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query("1"), "cuckoo filter should be empty")


cf = cuckoo_filter_expire.new(512, 1)
local ns, interval = cf:current_interval()
assert(ns == 15300000000000, tostring(ns))
assert(interval == 255, tostring(interval))
for i=1, 410 do
   cf:add(i, 60e9)
end
local added, delta =  cf:add(200, 120e9)
assert(not added)
assert(delta == 1, tostring(delta))
assert(cf:count() == 410, "count=" .. cf:count())
cf:add(411, 120e0) -- expired everything by capacity
assert(cf:count() == 2, "count=" .. cf:count())

cf = cuckoo_filter_expire.new(512, 60)
for i=1, 410 do
   cf:add(i, 3600e9)
end
added, delta =  cf:add(200, 7200e9)
assert(not added)
assert(delta == 1, tostring(delta))
assert(cf:count() == 410, "count=" .. cf:count())
cf:add(411, 7200e9) -- expired everything by capacity
assert(cf:count() == 2, "count=" .. cf:count())

cf = cuckoo_filter_expire.new(512, 1440)
for i=1, 410 do
   cf:add(i, 86400e9)
end
added, delta =  cf:add(200, 86400e9 * 2)
assert(not added)
assert(delta == 1, tostring(delta))
assert(cf:count() == 410, "count=" .. cf:count())
cf:add(411, 86400e9 * 2) -- expired everything by capacity
assert(cf:count() == 2, "count=" .. cf:count())

--[[ big test
require "math"
cf = cuckoo_filter_expire.new(256e6, 1)
local total = math.floor(1024 * 1024 * 256 * 0.8)
for i=1, total do
    cf:add(i, 60)
end
assert(cf:count() == total, "count=" .. cf:count())
--]]
