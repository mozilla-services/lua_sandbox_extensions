-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "hyperloglog"
require "string"
assert(hyperloglog.version() == "1.0.0", hyperloglog.version())

local hll = hyperloglog.new()
local hll1 = hyperloglog.new()
local hll2 = hyperloglog.new()
local base = hyperloglog.new()

for i=1, 110000 do
    base:add(string.format("%08d", i))
end
local expected = 110505
assert(base:count() == expected, string.format("incorect count expected: %d, received: %d", expected, base:count()))

local expected = 0
assert(hll:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll:count()))

local expected = 50000
for i=1, 50000 do
    hll:add(string.format("%08d", i))
end
expected = 49932
assert(hll:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll:count()))
hll1:merge(hll)
assert(hll1:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll1:count()))

local hll_str = tostring(hll)
assert(#hll_str == 12304, #hll_str)

local hll_restored = hyperloglog.new()
hll_restored:fromstring(hll_str)
assert(hll_restored:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll_restored:count()))

for i=100001, 110000 do
    hll1:add(string.format("%08d", i))
end
expected = 59872
local count = hyperloglog.count(hll, hll1)
assert(count == expected, string.format("incorect count expected: %d, received: %d", expected, count))

for i=50001, 100000 do
    hll2:add(string.format("%08d", i))
end
expected = 50151
assert(hll2:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll2:count()))

expected = 110383
count = hyperloglog.count(hll, hll1, hll2)
assert(count == expected, string.format("incorect count expected: %d, received: %d", expected, count))

hll:clear()

local hll_str = tostring(hll)
assert(#hll_str == 12304, #hll_str)

expected = 0
assert(hll:count() == expected, string.format("incorect count expected: %d, received: %d", expected, hll:count()))

local ok, err = pcall(hyperloglog.new, 2)
assert(err == "bad argument #1 to '?' (incorrect number of arguments)", err)

ok, err = pcall(hyperloglog.count)
assert(err == "bad argument #0 to '?' (incorrect number of arguments)", err)

ok, err = pcall(hll.add, hll, {})
assert(err == "bad argument #2 to '?' (must be a string or number)", err)
ok, err = pcall(hll.fromstring, hll, {})
assert(err == "bad argument #2 to '?' (string expected, got table)", err)
ok, err = pcall(hll.fromstring, hll, "      ")
assert(err == "fromstring() bytes found: 6, expected 12304", err)
ok, err = pcall(hll.add, hll)
assert(err == "bad argument #1 to '?' (incorrect number of arguments)", err)
ok, err = pcall(hll.count, hll, 1)
assert(err == "bad argument #2 to '?' (incorrect number of arguments)", err)
ok, err = pcall(hll.clear, hll, 1)
assert(err == "bad argument #2 to '?' (incorrect number of arguments)", err)
ok, err = pcall(hll.merge)
assert(err == "bad argument #0 to '?' (incorrect number of arguments)", err)
ok, err = pcall(hll.merge, hll, {})
assert(err == "bad argument #2 to '?' (mozsvc.hyperloglog expected, got table)", err)
