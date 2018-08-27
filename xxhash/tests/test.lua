-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "xxhash"

local errors = {
    function() local h = xxhash.h32() end, -- incorrect # args
    function() local h = xxhash.h64() end, -- incorrect # args
    function() local h = xxhash.h32(nil) end, -- invalid item
    function() local h = xxhash.h64(nil) end, -- invalid item
    function() local h = xxhash.h32("foo", -1) end, -- invalid seed
    function() local h = xxhash.h32("foo", "a") end, -- invalid seed
    function() local h = xxhash.h32("foo", 4.3e9) end, -- invalid seed
    function() local h = xxhash.h64("foo", -1) end, -- invalid seed
    function() local h = xxhash.h64("foo", "a") end, -- invalid seed
    function() local h = xxhash.h64("foo", 1.85e19) end, -- invalid seed
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

local h
h = xxhash.h32("foobar")
assert(h == 3986901679, h)
h = xxhash.h32("foobar", 0)
assert(h == 3986901679, h)
h = xxhash.h32("foobar", 1)
assert(h == 366339015, h)
h = xxhash.h32(123)
assert(h == 1710687148, h)
h = xxhash.h32(123, 1)
assert(h == 1102037802, h)
h = xxhash.h32(123, 4.2e9)
assert(h == 545974333, h)

h = xxhash.h64("foobar")
assert(h == 11721187498075203584, string.format("%u", h))
h = xxhash.h64("foobar", 0)
assert(h == 11721187498075203584, string.format("%u", h))
h = xxhash.h64("foobar", 1)
assert(h == 17884410770440888320, string.format("%u", h))
h = xxhash.h64(123)
assert(h == 1712328529600727296, string.format("%u", h))
h = xxhash.h64(123, 1.84e19)
assert(h == 6456655639160719360, string.format("%u", h))
