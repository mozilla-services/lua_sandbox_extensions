-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

function read_config()
    return {
        disabled = true,
        modules = {},
        thresholds = {},
        }
end
require "math"
local mth = require "moz_telemetry.histogram"


local function verify_buckets(buckets, expected)
    local t = type(buckets)
    assert(t == "table", t)
    for i,v in ipairs(expected) do
        assert(i - 1 == buckets[v], string.format("index: %d value: %s", i, tostring(buckets[v])))
    end
end

local expected = {0, 1, 6, 33, 184, 1028, 5741, 32062, 179059, 1000000}
local buckets = mth.get_exponential_buckets(1, 1000000, 10)
verify_buckets(buckets, expected)
local cache = {}
buckets = mth.get_exponential_buckets(1, 1000000, 10, cache)
verify_buckets(buckets, expected)
assert(buckets == mth.get_exponential_buckets(1, 1000000, 10, cache))

local histograms = mth.create(2, cache)
local json = {exp = {histogram_type = 0, range = {1,1000000}, bucket_count = 10,
    values = {["0"] = 1, ["1"] = 2, ["6"] = 3, ["33"] = 4, ["184"] = 5,
        ["1028"] = 6, ["5741"] = 7, ["32062"] = 8, ["179059"] = 9, ["1000000"] = 10}}}
mth.process(12345e9, json, histograms, 2)
local exp = histograms.names.exp
assert(exp)
assert(exp.histogram_type == 0, exp.histogram_type)
local v = exp.submissions:get(1, 1)
assert(v == 0, v)
v = exp.submissions:get(2, 1)
assert(v == 1, v)
assert(exp.created == 12345, exp.created)
assert(exp.updated == 12345, exp.updated)
assert(exp.bucket_count == 10, exp.bucket_count)
assert(exp.alerted == false, exp.alerted)
verify_buckets(exp.buckets, expected)
for i=1, 10 do
    local v = exp.data:get(2, i)
    assert(v == math.floor(i / 55 * 1000), string.format("index: %d, value: %d", i, v))
end

mth.process(12346e9, json, histograms, 2)
local exp1 = exp
exp = histograms.names.exp
assert(exp == exp1)
v = exp.submissions:get(2, 1)
assert(v == 2, v)
assert(exp.updated == 12346, exp.updated)
for i=1, 10 do
    local v = exp.data:get(2, i)
    assert(v == math.floor(i / 55 * 1000) * 2, string.format("index: %d, value: %d", i, v))
end


json = {lin = {histogram_type = 1, range = {1,1000}, bucket_count = 10,
    values = {["0"] = 1, ["1"] = 2, ["126"] = 3, ["251"] = 4, ["376"] = 5,
        ["501"] = 6, ["625"] = 7, ["750"] = 8, ["875"] = 9, ["1000"] = 10}}}
mth.process(12335e9, json, histograms, 2)
local lin = histograms.names.lin
assert(lin)
assert(lin.histogram_type == 1, lin.histogram_type)
v = lin.submissions:get(2, 1)
assert(v == 1, v)
assert(lin.created == 12335, lin.created)
assert(lin.updated == 12335, lin.updated)
assert(lin.bucket_count == 10, lin.bucket_count)
assert(lin.alerted == false, lin.alerted)
for i=1, 10 do
    local v = lin.data:get(2, i)
    assert(v == math.floor(i / 55 * 1000), string.format("index: %d, value: %d", i, v))
end

mth.process(12336e9, json, histograms, 2)
local lin1 = lin
lin = histograms.names.lin
assert(lin == lin1)
v = lin.submissions:get(2, 1)
assert(v == 2, v)
assert(lin.updated == 12336, lin.updated)
for i=1, 10 do
    local v = lin.data:get(2, i)
    assert(v == math.floor(i / 55 * 1000) * 2, string.format("index: %d, value: %d", i, v))
end

mth.clear_row(histograms, 2)
v = exp.submissions:get(2, 1)
assert(v == 0, v)
v = lin.submissions:get(2, 1)
assert(v == 0, v)
for i=1, 10 do
    local v = exp.data:get(2, i)
    assert(v == 0, string.format("index: %d, value: %d", i, v))
    v = lin.data:get(2, i)
    assert(v == 0, string.format("index: %d, value: %d", i, v))
end

return 0
