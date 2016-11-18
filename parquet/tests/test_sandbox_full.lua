-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "parquet"
require "string"
local parser = require "lpeg.parquet"

local schema = [[
message test {
    required fixed_len_byte_array(16) Uuid;
    required int64 Timestamp;
    required binary Logger;
    required binary Hostname;
    required binary Type;
    required binary Payload;
    required binary EnvVersion;
    required int32 Pid;
    required int32 Severity;
    required group Fields {
        required boolean bool;
        repeated boolean bools;
        required int32 int;
        repeated int32 ints;
        required int64 int64;
        repeated int64 int64s;
        required float float;
        repeated float floats;
        required double double;
        repeated double doubles;
        required binary binary;
        repeated binary binaries;
        required fixed_len_byte_array(5) flba;
        repeated fixed_len_byte_array(5) flbas;
        required int96 int96;
        repeated int96 int96s;
        optional binary missing;
    }
}
]]

local s = parser.load_parquet_schema(schema)
local hs = parser.load_parquet_schema(schema, true)
function process_message()
    local w = parquet.writer("hm.parquet", s)
    w:dissect_message()
    w:close()

    w = parquet.writer("hm_hive.parquet", hs)
    w:dissect_message()
    w:close()
    return 0
end

function time_event()
end

