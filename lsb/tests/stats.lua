-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "math"
require "string"
local stats = require "lsb.stats"

local basic_tests = {
    {sum = 10, avg = 2.5, min = 1, max = 4, variance = 1.25, sd = math.sqrt(1.25), array = {0/0,1,2,3,4}, size = 4},
    {sum = 0, avg = 0, min = 0/0, max = 0/0, variance = 0, sd = 0, array = {0/0,0/0,0/0}, size = 0}
}

local function test_basic_stats()
    for i,v in ipairs(basic_tests) do
        for m, stat in ipairs({"sum", "avg", "min", "max", "variance", "sd"}) do
            local d, c = stats[stat](v.array)
            local expected = v[stat]
            if expected == expected then
                assert(d == v[stat], string.format("test: %d stat: %s received: %s", i, stat, tostring(d)))
            else
                assert(d ~= d, string.format("test: %d stat: %s received: %s", i, stat, tostring(d)))
            end
            assert(c == v.size, string.format("test: %d stat: %s size: %s", i, stat, tostring(c)))
        end
    end
end


local range_tests = {
    {sum = 6, avg = 2, min = 1, max = 3, variance = 2/3, sd = math.sqrt(2/3), array = {0/0,1,2,3,4}, size = 3},
    {sum = 0, avg = 0, min = 0/0, max = 0/0, variance = 0, sd = 0, array = {0/0,0/0,0/0}, size = 0}
}

local function test_range_stats()
    for i,v in ipairs(range_tests) do
        for m, stat in ipairs({"sum", "avg", "min", "max", "variance", "sd"}) do
            local d, c = stats[stat](v.array, 2, 4)
            local expected = v[stat]
            if expected == expected then
                assert(d == v[stat], string.format("test: %d stat: %s received: %s", i, stat, tostring(d)))
            else
                assert(d ~= d, string.format("test: %d stat: %s received: %s", i, stat, tostring(d)))
            end
            assert(c == v.size, string.format("test: %d stat: %s size: %s", i, stat, tostring(c)))
        end
    end
end


local ndtr_tests = {
    {d = 0/0, x = 0/0},
    {d = 0.841344, x = 1},
    {d = 0.977249, x = 2},
    {d = 0.998650, x = 3},
}

local function test_ndtr()
    for i,v in ipairs(ndtr_tests) do
        local d = stats.ndtr(v.x)
        if v.d == v.d then
            assert(math.abs(d - v.d) < 0.000001, string.format("test: %d received: %g", i, d))
        else
            assert(d ~= d, string.format("test: %d received: %g", i , d))
        end
    end
end


local mww_tests = {
    {u = 0, p = 0.006092, x = {10,20,30,40,50}, y = {60,70,80,90,100}, continuity = true},
    {u = nil, p = nil, x = {1,1,1,1,1,1,1,1,1,1}, y = {1,1,1,1,1,1,1,1,1,1}, continuity = true},
    {u = 171, p = 0.220374, -- default
        x = {15309,14092,13661,13412,14205,15042,14142,13820,14917,13953,14320,14472,15133,13790,14539,14129,14363,14202,13841,13610},
        y = {13759,14428,14851,13838,13819,14468,14989,15557,14380,13500,14818,14632,13631,14663,14532,14188,14537,14109,13925,15022}},
    {u = 171, p = 0.216387, -- no continuity correction
        x = {15309,14092,13661,13412,14205,15042,14142,13820,14917,13953,14320,14472,15133,13790,14539,14129,14363,14202,13841,13610},
        y = {13759,14428,14851,13838,13819,14468,14989,15557,14380,13500,14818,14632,13631,14663,14532,14188,14537,14109,13925,15022},
        continuity = false},
    {u = 168.5, p = 0.200849, -- tie correction
        x = {15309,14092,13661,13412,14205,15042,14142,13820,14917,13953,14320,14472,15133,13790,14539,14129,14363,14202,13841,13610},
        y = {13759,14428,14851,13838,13819,14468,14989,15557,14380,13500,14818,14632,13631,14663,14532,14188,14537,14109,13925,15309}},
    {u = 1882, p = 0.328868,
        x = {1,1,1,2,1,3,3,6,4,0/0,0/0,0/0,1,0/0,2,0/0,0/0,0/0,0/0,0/0,1,5,1,0/0,1,1,0/0,0/0,3,4,1,1,1,0/0,7,1,0/0,6,0/0,0/0,1,3,4,3,0/0,1,5,0/0,1,0/0,0/0,1,6,4,0/0,4,2,6,4,3},
        y = {2,6,2,11,2,0/0,2,0/0,2,0/0,0/0,0/0,4,0/0,3,2,0/0,0/0,1,2,2,2,1,1,0/0,3,0/0,4,0/0,0/0,2,3,5,6,3,1,0/0,0/0,3,2,0/0,4,1,2,1,1,0/0,0/0,0/0,0/0,0/0,0/0,0/0,7,1,1,2,1,0/0,0/0}},
    {u = 1718, p = 0.328868,
        y = {1,1,1,2,1,3,3,6,4,0/0,0/0,0/0,1,0/0,2,0/0,0/0,0/0,0/0,0/0,1,5,1,0/0,1,1,0/0,0/0,3,4,1,1,1,0/0,7,1,0/0,6,0/0,0/0,1,3,4,3,0/0,1,5,0/0,1,0/0,0/0,1,6,4,0/0,4,2,6,4,3},
        x = {2,6,2,11,2,0/0,2,0/0,2,0/0,0/0,0/0,4,0/0,3,2,0/0,0/0,1,2,2,2,1,1,0/0,3,0/0,4,0/0,0/0,2,3,5,6,3,1,0/0,0/0,3,2,0/0,4,1,2,1,1,0/0,0/0,0/0,0/0,0/0,0/0,0/0,7,1,1,2,1,0/0,0/0}},
    }

local function test_mannwhitneyu()
    for i,v in ipairs(mww_tests) do
        local u, p = stats.mannwhitneyu(v.x, v.y, v.continuity)
        assert(u == v.u, string.format("test:%d received u: %s", i, tostring(u)))
        if p then
            assert(math.abs(p - v.p) < 0.000001, string.format("test: %d received p: %s", i, tostring(p)))
        else
            assert(p == v.p)
        end
    end
end


test_basic_stats()
test_range_stats()
test_ndtr()
test_mannwhitneyu()
