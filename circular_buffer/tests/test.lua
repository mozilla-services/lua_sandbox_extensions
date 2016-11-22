-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "circular_buffer"
require "string"
require "lpeg"
local cbufd = require "lpeg.cbufd"
assert(circular_buffer.version() == "1.0.2", circular_buffer.version())

local errors = {
    function() local cb = circular_buffer.new(2) end, -- new() incorrect # args
    function() local cb = circular_buffer.new(nil, 1, 1) end, -- new() non numeric row
    function() local cb = circular_buffer.new(1, 1, 1) end, -- new() 1 row
    function() local cb = circular_buffer.new(2, nil, 1) end,-- new() non numeric column
    function() local cb = circular_buffer.new(2, 0, 1) end, -- new() zero column
    function() local cb = circular_buffer.new(2, 1, nil) end, -- new() non numeric seconds_per_row
    function() local cb = circular_buffer.new(2, 1, 0) end, -- new() zero seconds_per_row
    function() local cb = circular_buffer.new(2, 257, 0) end, -- new() too many columns
    function() local cb = circular_buffer.new(2, 1, 1) -- set() out of range column
    cb:set(0, 2, 1.0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- set() zero column
    cb:set(0, 0, 1.0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- set() non numeric column
    cb:set(0, nil, 1.0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- set() non numeric time
    cb:set(nil, 1, 1.0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- get() invalid object
    local invalid = 1
    cb.get(invalid, 1, 1) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- set() non numeric value
    cb:set(0, 1, nil) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- set() incorrect # args
    cb:set(0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- add() incorrect # args
    cb:add(0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- get() incorrect # args
    cb:get(0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- get_range() incorrect # args
    cb:get_range() end,
    function() local cb = circular_buffer.new(2, 1, 1) -- get_range() incorrect column
    cb:get_range(0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- get_range() start > end
    cb:get_range(1, 2e9, 1e9) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- format() invalid
    cb:format("invalid") end,
    function() local cb = circular_buffer.new(2, 1, 1) -- format() extra
    cb:format("cbuf", true) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- format() missing
    cb:format() end,
    function() local cb = circular_buffer.new(10, 1, 1)
    cb:get_header() end, -- incorrect # args
    function() local cb = circular_buffer.new(10, 1, 1)
    cb:get_header(99) end, -- out of range column
    function() local cb = circular_buffer.new(2, 1, 1) -- uninitialize a value
    cb:set(0, 1, 1); cb:set(0, 1, 0/0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- uninitialize a value
    cb:set(0, 1, 1); cb:add(0, 1, 0/0) end,
    function() local cb = circular_buffer.new(2, 1, 1) -- NAN result
    cb:set(0, 1, 1/0); cb:add(0, 1, -1/0) end,
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

local tests = {
    function()
        local stats = circular_buffer.new(5, 1, 1)
        stats:set(1e9, 1, 1)
        stats:set(2e9, 1, 2)
        stats:set(3e9, 1, 3)
        stats:set(4e9, 1, 4)
        stats:set(5e9, 1, 5)

        local a = stats:get_range(1)
        assert(#a == 5, #a)
        for i=1, #a do assert(i == a[i]) end

        a = stats:get_range(1, 3e9, 4e9)
        assert(#a == 2, #a)
        for i=3, 4 do assert(i == a[i-2]) end

        a = stats:get_range(1, 3e9)
        assert(#a == 3, #a)
        for i=3, 5 do assert(i == a[i-2]) end

        a = stats:get_range(1, 3e9, nil)
        assert(#a == 3, #a)
        for i=3, 5 do assert(i == a[i-2]) end

        a = stats:get_range(1, 11e9, 14e9)
        if a then error(string.format("out of range %d", #a)) end

        a = stats:get_range_delta(1)
        assert(#a == 5, #a)
        for i=1, #a do assert(i == a[i]) end
        end,
    function()
        local stats = circular_buffer.new(2, 1, 1)
        local nan = stats:get(0, 1)
        if nan == nan then
            error(string.format("initial value is a number %G", nan))
        end
        nan = stats:get_delta(0, 1)
        if nan == nan then
            error(string.format("initial delta value is a number %G", nan))
        end

        local v = stats:set(0, 1, 1)
        if v ~= 1 then
            error(string.format("set failed = %G", v))
        end
        v = stats:get_delta(0, 1)
        if v ~= 1 then
            error(string.format("get_delta failed = %G", v))
        end
        end,
    function()
        local stats = circular_buffer.new(2, 1, 1)
        local cbuf_time = stats:current_time()
        if cbuf_time ~= 1e9 then
            error(string.format("current_time = %G", cbuf_time))
        end
        local v = stats:set(0, 1, 1)
        if stats:get(0, 1) ~= 1 then
            error(string.format("set failed = %G", v))
        end
        end,
    function()
        local cb = circular_buffer.new(10,1,1)
        local rows, cols, spr = cb:get_configuration()
        assert(rows == 10, "invalid rows")
        assert(cols == 1 , "invalid columns")
        assert(spr  == 1 , "invalid seconds_per_row")
        end,
    function()
        local cb = circular_buffer.new(10,1,1)
        local args = {"widget", "count", "max"}
        local col = cb:set_header(1, args[1], args[2], args[3])
        assert(col == 1, "invalid column")
        local n, u, m = cb:get_header(col)
        assert(n == args[1], "invalid name")
        assert(u == args[2], "invalid unit")
        assert(m == args[3], "invalid aggregation_method")
        end,
    function()
        local cb = circular_buffer.new(10,1,1)
        assert(not cb:get(10*1e9, 1), "value found beyond the end of the buffer")
        cb:set(20*1e9, 1, 1)
        assert(not cb:get(10*1e9, 1), "value found beyond the start of the buffer")
        end,
    function()
        local cb = circular_buffer.new(2,1,1)
        assert(1e9 == cb:current_time(), "current time not 1e9")
        local v = cb:set(3e9, 1, 0/0)
        assert(not (v == v), "advance the buffer with a NAN")
        assert(3e9 == cb:current_time(), "current time not 3e9")
        local v = cb:add(4e9, 1, 0/0)
        assert(not (v == v), "advance the buffer with a NAN")
        assert(4e9 == cb:current_time(), "current time not 4e9")
        end,
    function()
        local stats = circular_buffer.new(2, 4, 1)
        if not stats.reset_delta then return end

        stats:set_header(1, "count", "count", "sum")
        stats:set_header(2, "min", "count", "min")
        stats:set_header(3, "max", "count", "max")
        stats:set_header(4, "none", "avg", "none")
        local v

        -- deltas equal to the initial values
        v = stats:add(0, 1, 0)
        if v ~= 0 then error(string.format("add failed = %G", v)) end
        v = stats:get_delta(0, 1)
        if v ~= 0 then error(string.format("invalid delta value %G", v)) end

        v = stats:add(0, 2, -2)
        if v ~= -2 then error(string.format("add failed = %G", v)) end
        v = stats:get_delta(0, 2)
        if v ~= -2 then error(string.format("invalid delta value %G", v)) end

        v = stats:add(0, 3, -3)
        if v ~= -3 then error(string.format("add failed = %G", v)) end
        v = stats:get_delta(0, 3)
        if v ~= -3 then error(string.format("invalid delta value %G", v)) end

        v = stats:add(0, 4, 4)
        if v ~= 4 then error(string.format("add failed = %G", v)) end
        v = stats:get_delta(0, 4)
        if v == v then error(string.format("invalid delta value %G", v)) end

        -- updates with no change
        stats:reset_delta()
        v = stats:set(0, 1, 0)
        if v ~= 0 then error(string.format("sot failed = %G", v)) end
        v = stats:get_delta(0, 1)
        if v == v then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 1, stats:get(0, 1))
        if v ~= 0 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 1)
        if v == v then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 2, -1)
        if v ~= -2 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 2)
        if v == v then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 3, -4)
        if v ~= -3 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 3)
        if v == v then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 4, 4)
        if v ~= 4 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 4)
        if v == v then error(string.format("invalid delta value %G", v)) end

        -- update with change
        stats:reset_delta()
        v = stats:add(0, 1, 3)
        v = stats:add(0, 1, 2)
        if v ~= 5 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 1)
        if v ~= 5 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 2, -3) -- new min
        if v ~= -3 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 2) -- min not expressed as a delta
        if v ~= -3 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 3, -2) -- new max
        if v ~= -2 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 3) -- max not expressed as a delta
        if v ~= -2 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 4, 5)
        if v ~= 5 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 4)
        if v == v then error(string.format("invalid delta value %G", v)) end

        -- infinity tests
        stats:reset_delta()
        v = stats:set(0, 1, 1/0)
        if v ~= 1/0 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 1)
        if v ~= 1/0 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 2, -1/0) -- new min
        if v ~= -1/0 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 2) -- min not expressed as a delta
        if v ~= -1/0 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 3, 1/0) -- new max
        if v ~= 1/0 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 3) -- max not expressed as a delta
        if v ~= 1/0 then error(string.format("invalid delta value %G", v)) end

        v = stats:set(0, 4, 1/0) -- new max
        if v ~= 1/0 then error(string.format("set failed = %G", v)) end
        v = stats:get_delta(0, 4) -- max not expressed as a delta
        if v == v then error(string.format("invalid delta value %G", v)) end
        end,

    function()
        local t = lpeg.match(cbufd.grammar, "header\n1\t2\t3\n2\tnan\t-4\n3\t-4.56\t5.67\n")
        assert(t)

        if t.header ~= "header" then error("header:" .. t.header) end
        if t[1].time ~= 1e9 then error("col 1 timestamp:" .. t[1].time) end
        if t[1][1] ~= 2 then error("col 1 val 1:" .. t[1][1]) end
        if t[1][2] ~= 3 then error("col 1 val 2:" .. t[1][2]) end

        if t[2].time ~= 2e9 then error("col 2 timestamp:" .. t[2].time) end
        if t[2][1] == t[2][1] then error("col 2 val 1:" .. t[2][1]) end
        if t[2][2] ~= -4 then error("col 2 val 2:" .. t[2][2]) end

        if t[3].time ~= 3e9 then error("col 3 timestamp:" .. t[3].time) end
        if t[3][1] ~= -4.56 then error("col 3 val 1:" .. t[3][1]) end
        if t[3][2] ~= 5.67 then error("col 3 val 2:" .. t[3][2]) end
    end,
}

for i, v in ipairs(tests) do
  v()
end

