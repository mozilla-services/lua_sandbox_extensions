-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "parquet"
assert(parquet.version() == "0.0.4", parquet.version())

local r1 = {
    DocId = 10,
    Links = {Forward = {20, 40, 60}},
    Name = {
        {
            Language = {
                {Code = "en-us", Country = "us"},
                {Code = "en"}
            },
            Url = "http://A"
        },
        {
            Url = "http://B"
        },
        {
            Language = {Code = "en-gb", Country = "gb"}
        }
    }
}

local r2 = {
    DocId = 20,
    Links = {Backward = {10, 30}, Forward = 80},
    Name = {Url = "http://C"}
}

local r2bad = {
    DocId = 99,
    Links = {Backward = {11, 33}, Forward = true},
    Name = {Url = "http://D"}
}

local unfinalized = parquet.schema("unfinalized")

local doc = parquet.schema("Document")
doc:add_column("DocId", "required", "int64")

local links = doc:add_group("Links", "optional")
links:add_column("Backward", "repeated", "int64")
links:add_column("Forward", "repeated", "int64")

local name = doc:add_group("Name", "repeated")
local language = name:add_group("Language", "repeated")
language:add_column("Code", "required", "binary")
language:add_column("Country", "optional", "binary")
name:add_column("Url", "optional", "binary")
doc:finalize()

local writer = parquet.writer("example.parquet", doc, {
    created_by = "hindsight",
    enable_statistics = true,
    columns = {
        ["Name.Url"] = {compression = "gzip"}
    }
})

writer:dissect_record(r1)
local ok, err = pcall(writer.dissect_record, writer, r2bad)
assert(not ok)
writer:write_rowgroup()
writer:dissect_record(r2)
writer:close()

local empty = parquet.schema("empty")
local nested = empty:add_group("nested", "optional")
local ok, err = pcall(empty.finalize, empty)
assert(not ok)

local finalized = parquet.schema("finalized")
local g1 = finalized:add_group("g1", "repeated", "list")
g1:add_column("name", "required", "binary")
g1:add_column("address", "required", "binary")
finalized:finalize()
finalized:finalize() -- no op

local ok, err = pcall(finalized.add_group, finalized, "n1", "repeated")
assert(not ok)
local ok, err = pcall(finalized.add_column, finalized, "f", "optional", "int64")
assert(not ok)

local ok, err = pcall(g1.add_group, g1, "n1", "optional")
assert(not ok)
local ok, err = pcall(g1.add_column, g1, "f", "optional", "int64")
assert(not ok)

local fw = parquet.writer("finalized.parquet", finalized)
fw:dissect_record(r1)
fw:close()
local ok, err = pcall(writer.dissect_record, fw, r1)
assert(not ok, "writer closed")

local ooe = parquet.schema("one_of_each")
ooe:add_column("b", "required", "boolean")
ooe:add_column("i32", "required", "int32")
ooe:add_column("i32ps", "required", "int32", "decimal", nil, 3, 2)
ooe:add_column("i64", "required", "int64")
ooe:add_column("i96", "required", "int96")
ooe:add_column("f", "required", "float")
ooe:add_column("d", "required", "double")
ooe:add_column("ba", "required", "binary")
ooe:add_column("flba", "required", "fixed_len_byte_array", nil, 5)
ooe:finalize()

local w = parquet.writer("one_of_each.parquet", ooe)
w:dissect_record(
    {
        b = true,
        i32 = 32,
        i32ps = 5280,
        i64 = 64,
        i96 = "abcdefghijkl",
        f = 1.12,
        d = 234.56789,
        ba = "this is a test",
        flba = "fixed"
    })


local dupe = parquet.schema("dupe")
dupe:add_column("b", "required", "boolean")
dupe:add_column("b", "required", "boolean")
dupe:finalize()

local dw = parquet.writer("dupe.parquet", dupe)
dw:dissect_record({b = true})

local ok, err = pcall(parquet.writer, "unfinalized", unfinalized)
assert(not ok)


local example_schema = [[
message Document {
  required int64 DocId;
  optional group Links {
    repeated int64 Backward;
    repeated int64 Forward;
  }
  repeated group Name (LIST) {
    repeated group Language {
      required binary Code;
      optional binary Country;
    }
    optional binary Url;
  }
}
]]

local parser = require "lpeg.parquet"
local shared = parser.load_parquet_schema(example_schema)

local w1 = parquet.writer("shared1.parquet", shared)
local w2 = parquet.writer("shared2.parquet", shared)
w1:dissect_record(r1)
w1:dissect_record(r2)
w2:dissect_record(r1)
w2:dissect_record(r2)
w1:close()
w2:close()

local hive = parser.load_parquet_schema(example_schema, true)
local w1 = parquet.writer("hive_example.parquet", hive)
w1:dissect_record(r1)
w1:dissect_record(r2)
w1:close()



local rtypes = {
    string = "s1",
    strings = {"s2, s3"},
    bool = true,
    bools = {false, false},
    int = 1,
    ints = {2, 3},
    number = 1.1,
    numbers = {1.2, 1.3},
    empty = {},
    fn = string.format,
    Fields = {}
}

local function test_schema_errors()
    local errs = {
        {"message test { required int64 missing; }", "column 'missing' is required"},
        {"message test { required int64 string; }", "column 'string' data type mismatch (string)"},
        {"message test { required int64 bool; }", "column 'bool' data type mismatch (boolean)"},
        {"message test { required boolean int; }", "column 'int' data type mismatch (integer)"},
        {"message test { required group missing { required int32 int; }}", "group 'missing' is required"},
        {"message test { required binary fn; }", "column 'fn' unsupported data type: function"},
        {"message test { required group number { required int32 int; }}", "group 'number' expected, found data"},
        {"message test { required int32 numbers; }", "column 'numbers' should not be repeated"},
        {"message test { required fixed_len_byte_array(3) string; }", "column 'string' expected FIXED_LEN_BYTE_ARRAY(3) but received 2 bytes"},
        {"message test { required int96 string; }", "column 'string' expected INT96 but received 2 bytes"},
        {"message test { repeated group Fields { required binary foo; }}", "column 'foo' is required"},
    }

    for i,v in ipairs(errs) do
        local s = parser.load_parquet_schema(v[1])
        local w = parquet.writer("error.parquet", s)
        local ok, err = pcall(w.dissect_record, w, rtypes)
        assert(err == v[2], string.format("Test: %d expected: %s received: %s", i, v[2], tostring(err)))
    end
end

test_schema_errors()
