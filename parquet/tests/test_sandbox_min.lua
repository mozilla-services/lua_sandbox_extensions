-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "parquet"
require "string"
local parser = require "lpeg.parquet"

local errs = {
    {"message test { required binary Logger; }", "column 'Logger' is required"},
    {"message test { required binary Hostname; }", "column 'Hostname' is required"},
    {"message test { required binary Type; }", "column 'Type' is required"},
    {"message test { required binary Payload; }", "column 'Payload' is required"},
    {"message test { required binary EnvVersion; }", "column 'EnvVersion' is required"},
    {"message test { required int32 Pid; }", "column 'Pid' is required"},
    {"message test { required group Fields { required binary foo; }}", "column 'foo' is required"},
    {"message test { required group Fields { required group nested { required binary foo; }}}", "group 'nested' not allowed in Fields"},
    {"message test { required binary unknown; }", "column 'unknown' invalid schema"},
    {"message test { required group extra { required binary foo; }}", "group 'extra' invalid schema"},
}

function process_message()
    for i,v in ipairs(errs) do
        local s = parser.load_parquet_schema(v[1])
        local w = parquet.writer("error.parquet", s)
        local ok, err = pcall(w.dissect_message, w)
        assert(err == v[2], string.format("Test: %d expected: %s received: %s", i, v[2], tostring(err)))
    end
    return 0
end

function time_event()
end

