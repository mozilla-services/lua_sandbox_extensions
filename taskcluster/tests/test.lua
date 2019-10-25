-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local util = require "taskcluster.util"

local function test_get_time_t()
    local tests = {
        {"2019-10-22T10:11:12", 1571739072},
        {"foo", nil}
    }
    for i,v in ipairs(tests) do
        local rv1 = util.get_time_t(v[1])
        assert(rv1 == v[2], rv1)
    end
end


local function test_get_time_m()
    local tests = {
        {"2019-10-22T10:11:12", 1571739060, 1571739072},
        {"foo", nil, nil}
    }
    for i,v in ipairs(tests) do
        local rv1, rv2= util.get_time_m(v[1])
        assert(rv1 == v[2], rv1)
        assert(rv2 == v[3], rv2)
    end
end


local function test_normalize_workertype()
    local tests = {
        {"foobar", "foobar"},
        {"test-RaNdoM-a", "test-generic"},
        {"dummy-worker-anything", "dummy-worker"},
        {"dummy-type-anything-a", "dummy-type"},
        {nil, "_"}
    }
    for i,v in ipairs(tests) do
        local rv1= util.normalize_workertype(v[1])
        assert(rv1 == v[2], rv1)
    end
end

test_get_time_t()
test_get_time_m()
test_normalize_workertype()
