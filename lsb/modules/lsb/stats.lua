-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Lua Sandbox Stats Module

## Functions

### sum

Sum an array of numbers ignoring NaN.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- sum (number)
- count (integer) - number of items summed (non NaN)

### avg

Average an array of numbers ignoring NaN.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- avg (number)
- count (integer) - number of items averaged (non NaN)

### min

Return the minimum value in an array of numbers.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- min (number)
- count (integer) - number of items compared (non NaN)

### max

Return the maximum value in an array of numbers.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- max (number)
- count (integer) - number of items compared (non NaN)

### variance

Return the variance of an array of numbers.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- variance (number)
- count (integer) - number of items in the calculation (non NaN)

### sd

Return the standard deviation of an array of numbers.

*Arguments*
- array (table)
- start (number, nil) - start index in the array (if nil 1)
- end (number, nil) - end index in the array (if nil #array)

*Return*
- sd (number)
- count (integer) - number of items in the calculation (non NaN)

### ndtr

Normal ditribution function.

*Arguments*
- x (number)

*Return*
- a (number) - returns the area under the Gaussian probability density function,
  integrated from minus infinity to x

### mannwhitneyu

Computes the Mann-Whitney rank test on arrays x and y.

*Arguments*
- x (table)
- y (table)
- use_continuity (bool) - whether a continuity correction (1/2) should be taken
  into account (default: true)

*Return*
- u (number) - Mann-Whitney U statistic, equal to min(u for x, u for y)
- p (number) - one-sided p-value assuming a asymptotic normal distribution

**Note:** Use only when the number of observation in each sample is > 20 and you
have 2 independent samples of ranks.  Mann-Whitney U is significant if the
u obtained is LESS THAN or equal to the critical value of u.

This test corrects for ties and by default uses a continuity correction. The
reported p-value is for a one-sided hypothesis, to get the two-sided p-value
multiply the returned p-value by 2.

--]]

-- Imports
require "math"
require "table"

local ipairs = ipairs
local abs    = math.abs
local erf    = math.erf
local erfc   = math.erfc
local huge   = math.huge
local pow    = math.pow
local sqrt   = math.sqrt
local sort   = table.sort

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module


function sum(a, s, e)
    if not s then s = 1 end
    if not e then e = #a end
    local sum = 0
    local count = 0
    for i = s, e do
        local v = a[i]
        if v and v == v then -- test for NaN
            sum = sum + v
            count = count + 1
        end
    end
    return sum, count
end


function avg(a, s, e)
    local sum, count = sum(a, s, e)
    if count == 0 then return 0, 0 end
    return sum / count, count
end


function min(a, s, e)
    if not s then s = 1 end
    if not e then e = #a end
    local mv = huge
    local count = 0
    for i = s, e do
        local v = a[i]
        if v and v == v then -- test for NaN
            if v < mv then mv = v end
            count = count + 1
        end
    end
    if count == 0 then mv = 0/0 end
    return mv, count
end


function max(a, s, e)
    if not s then s = 1 end
    if not e then e = #a end

    local mv = -huge
    local count = 0
    for i = s, e do
        local v = a[i]
        if v and v == v then -- test for NaN
            if v > mv then mv = v end
            count = count + 1
        end
    end
    if count == 0 then mv = 0/0 end
    return mv, count
end


function variance(a, s, e)
    if not s then s = 1 end
    if not e then e = #a end

    local avg, count = avg(a, s, e)
    if count == 0 then return avg, count end

    local sos = 0
    for i = s, e do
        local v = a[i]
        if v and v == v then -- test for NaN
            v = v - avg
            sos = sos + v * v
        end
    end
    return sos / count, count
end


function sd(a, s, e)
    local v, c = variance(a, s, e)
    return sqrt(v), c
end


local function double_sort(s1, s2)
    local a = s1[1]
    local b = s2[1]
    if a ~= a and b ~= b then return false end
    if a ~= a then return true end
    if a < b then return true end
    return false
end


local function rank_data(sorted, sorted_size)
    local next = 0
    local dupe_count = 0
    local tie_correction = 0
    for i,v in ipairs(sorted) do
        next = i + 1
        if i == sorted_size
        or (not (v[1] ~= v[1] and sorted[next][1] ~= sorted[next][1]) and v[1] ~= sorted[next][1]) then
            if dupe_count ~= 0 then
                local tie_rank = i - 0.5 * dupe_count;
                for j = i - dupe_count, i do
                    sorted[j][1] = tie_rank
                end
                dupe_count = dupe_count + 1
                tie_correction = tie_correction + pow(dupe_count, 3) - dupe_count
                dupe_count = 0
            else
                sorted[i][1] = i
            end
        else
            dupe_count = dupe_count + 1
        end
    end
    tie_correction = 1 - tie_correction / (pow(sorted_size, 3) - sorted_size)
    return tie_correction
end


local SQRTH = 0.70710678118654752440 -- sqrt(2)/2
function ndtr(a)
    if a ~= a then return a end

    local y
    local x = a * SQRTH
    local z = abs(x)
    if z < SQRTH then
        y = 0.5 + 0.5 * erf(x)
    else
        y = 0.5 * erfc(z)
    end
    if x > 0 then y = 1 - y end
    return y
end


function mannwhitneyu(x, y, use_continuity)
    if use_continuity == nil then use_continuity = true end
    local n1 = #x
    local n2 = #y
    local sorted = {}

    for i,v in ipairs(x) do
        sorted[i] = {v, true}
    end

    for i,v in ipairs(y) do
        sorted[n1 + i] = {v}
    end
    sort(sorted, double_sort)
    local tie_correction = rank_data(sorted, n1 + n2)
    if tie_correction == 0 then return end

    local sum = 0
    for i,v in ipairs(sorted) do
        if v[2] then
            sum = sum + v[1]
        end
    end

    local u1 = sum - (n1 * (n1 + 1)) / 2
    local u2 = n1 * n2 - u1
    local lu
    if u1 > u2 then
        lu = u1
    else
        lu = u2
    end

    local z = 0
    local sd = sqrt(tie_correction * n1 * n2 * (n1 + n2 + 1) / 12.0);
    if use_continuity then
        -- normal approximation for prob calc with continuity correction
        z = abs((lu - 0.5 - n1 * n2 / 2.0) / sd);
    else
        -- normal approximation for prob calc
        z = abs((lu - n1 * n2 / 2.0) / sd);
    end

    return u1, ndtr(-z)
end

return M
