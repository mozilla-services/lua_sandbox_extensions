-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cuckoo_filter"
assert(cuckoo_filter.version() == "1.0.0", cuckoo_filter.version())

local errors = {
    function() local cf = cuckoo_filter.new(2, 99) end, -- new() incorrect # args
    function() local cf = cuckoo_filter.new(nil) end, -- new() non numeric item
    function() local cf = cuckoo_filter.new(0) end, -- invalid items
    function()
        local cf = cuckoo_filter.new()
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
   cf:add(i)
end
assert(cf:count() == 799987, "count=" .. cf:count())

for i=1, test_items do
    assert(cf:query(i), "query failed " .. i .. " " .. cf:count())
end

local dcnt = 0
for i=1, test_items do
   if cf:delete(i) then
       dcnt = dcnt + 1
   end
end
assert(dcnt == 799987, "deleted count=" .. dcnt)
assert(cf:count() == 0, "count=" .. cf:count())

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query(1), "cuckoo filter should be empty")

-- test strings
for i=1, test_items do
    cf:add(tostring(i))
end
assert(cf:count() == 799977, "count=" .. cf:count()) -- lower acuracy is expected since the string only use 0-9

for i=1, test_items do
    assert(cf:query(tostring(i)), "query failed")
end
assert(cf:delete("500000"))
assert(cf:count() == 799976, "count=" .. cf:count())

cf:clear()
assert(cf:count() == 0, "cuckoo filter should be empty")
assert(not cf:query("1"), "cuckoo filter should be empty")
