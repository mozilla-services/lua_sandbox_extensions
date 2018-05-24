-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "parquet"
assert(parquet.version() == "0.0.11", parquet.version())
local parser = require "lpeg.parquet"
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

local deprecated = parquet.schema("deprecated")
local ok, err = pcall(deprecated.add_group, deprecated, "mkv", "repeated", "map_key_value")
assert(err == "bad argument #4 to '?' (MAP_KEY_VALUE is deprecated)", err)

local finalized = parquet.schema("finalized")
local g1 = finalized:add_group("g1", "repeated")
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
  repeated group Name {
    repeated group Language {
      required binary Code;
      optional binary Country;
    }
    optional binary Url;
  }
}
]]

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


local function test_schema_dissection_errors()
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

test_schema_dissection_errors()


-- nested structs maps/lists
local function test_schema_finalize_errors()
    local errs = {
        {"message test { required group items (MAP) { repeated group key_value { optional binary key; required int32 value; } } }", "field 'key' must be a required primitive named 'key'"},
        {"message test { required group items (MAP) { repeated group key_value { repeated binary key; required int32 value; } } }", "field 'key' must be a required primitive named 'key'"},
        {"message test { required group items (MAP) { repeated group key_value { required binary foo; required int32 value; } } }", "field 'foo' must be a required primitive named 'key'"},
        {"message test { required group items (MAP) { repeated group key_value { required binary key; required int32 val; } } }", "field 'val' must be optional or required and named 'value'"},
        {"message test { required group items (MAP) { repeated group key_value { required binary key; repeated int32 value; } } }", "field 'value' must be optional or required and named 'value'"},
        {"message test { required group items (MAP) { repeated int32 key_value; } }", "field 'key_value' must be a repeated group named 'key_value'"},
        {"message test { required group items (MAP) { repeated group key_value { required binary key; required int32 value; } required int32 foo; } }", "group 'items' must be required or optional and contain a single group field"},
        {"message test { required group items (MAP) { repeated group key_value { required binary key; } } }", "group 'key_value' must have 2 fields"},
        {"message test { required group items (LIST) { repeated group list { required int32 element; } required int32 foo; } }", "group 'items' must be required or optional and contain a single group field"},
        {"message test { required group items (LIST) { repeated group list { required int32 foo; required int32 element; } } }", "group 'list' must have 1 field"},
        {"message test { required group items (LIST) { repeated group foo { required int32 element; } } }", "field 'foo' must be a repeated group named 'list'"},
        {"message test { required group items (LIST) { repeated group list { required int32 val; } } }", "field 'val' must be optional or required and named 'element'"},
    }

    for i,v in ipairs(errs) do
        local ok, err = pcall(parser.load_parquet_schema, v[1])
        assert(err == v[2], string.format("Test: %d expected: %s received: %s", i, v[2], tostring(err)))
    end
end

test_schema_finalize_errors()

local maps_schema = [[
message Document {
  required group my_map (MAP) {
    repeated group key_value {
      required binary key (UTF8);
      optional int32 value;
    }
  }
  optional group omap (MAP) {
    repeated group key_value {
      required binary key (UTF8);
      required int32 value;
    }
  }
  optional group mom (MAP) {
    repeated group key_value {
      required binary key (UTF8);
      required group value (MAP) {
        repeated group key_value {
          required binary key (UTF8);
          required int32 value;
        }
      }
    }
  }
}
]]

local function test_map_dissection()
    local recs = {
        {my_map = {foo = 1, bar = 2}},
        {my_map = {foo = 1, bar = parquet.null, blee = 2}},
        {my_map = {foo = 2}, omap = {bar = 3}},
        {my_map = {foo = 2}, omap = {}},
        {my_map = {foo = 99}, mom = {m1 = {nm1a = 100, nm1b = 101}, m2 = {nm2a = 200}}},
    }
    local s = parser.load_parquet_schema(maps_schema)
    local w = parquet.writer("maps.parquet", s)
    for i,v in ipairs(recs) do
        local ok, err = pcall(w.dissect_record, w, v)
        assert(ok, string.format("Test: %d err: %s", i, tostring(err)))
    end
end

test_map_dissection()

local function test_map_dissection_errors()
    local s = parser.load_parquet_schema(maps_schema)
    local errs = {
        {{}, "group 'my_map' is required"},
        {{my_map = {foo = "string"}}, "column 'value' data type mismatch (string)"},
        {{my_map = {[999] = 1}}, "column 'key' data type mismatch (integer)"},
        {{my_map = "foo"}, "group 'my_map' expected, found data"},
        {{my_map = {{foo = 1}}}, "column 'value' should not be repeated"},
        -- cannot test my_map optional value
    }
    for i,v in ipairs(errs) do
        local w = parquet.writer("maps_error.parquet", s)
        local ok, err = pcall(w.dissect_record, w, v[1])
        assert(err == v[2], string.format("Test: %d expected: %s received: %s", i, v[2], tostring(err)))
    end
end

test_map_dissection_errors()

local lists_schema = [[
message Document {
  required group my_list (LIST) {
    repeated group list {
      optional int32 element;
    }
  }
  optional group olist (LIST) {
    repeated group list {
      required int32 element;
    }
  }
  optional group lol (LIST) {
    repeated group list {
      required group element (LIST) {
        repeated group list {
          required int32 element;
        }
      }
    }
  }
}
]]

local function test_list_dissection()
    local recs = {
        {my_list = {1,2,3}},
        {my_list = {1,2,3}, olist = {10}},
        {my_list = {1,2, parquet.null, parquet.null, 4, parquet.null, 3}, lol = {{100, 101}, {200}}},
        {my_list = {1,2, nil, nil, 4, nil, 3}},
        {my_list = {1,2,3}, lol = {{}}},
    }
    local s = parser.load_parquet_schema(lists_schema)
    local w = parquet.writer("lists.parquet", s)
    for i,v in ipairs(recs) do
        local ok, err = pcall(w.dissect_record, w, v)
        assert(ok, string.format("Test: %d err: %s", i, tostring(err)))
    end
end

test_list_dissection()

local function test_list_dissection_errors()
    local s = parser.load_parquet_schema(lists_schema)
    local errs = {
        {{}, "group 'my_list' is required"},
        {{my_list = 10}, "group 'my_list' expected, found data"},
        {{my_list = {"foo"}}, "column 'element' data type mismatch (string)"},
        {{my_list = {{10}}}, "column 'element' should not be repeated"},

    }
    for i,v in ipairs(errs) do
        local w = parquet.writer("lists_error.parquet", s)
        local ok, err = pcall(w.dissect_record, w, v[1])
        assert(err == v[2], string.format("Test: %d expected: %s received: %s", i, v[2], tostring(err)))
    end
end

test_list_dissection_errors()


local tuple_schema = [[
message Document {
  required group element (TUPLE) {
    required int64 timestamp;
    required binary category (UTF8);
    required binary method (UTF8);
    required binary object (UTF8);
    optional binary value (UTF8);
    optional group extra (MAP) {
      repeated group key_value {
        required binary key (UTF8);
        required binary value (UTF8);
      }
    }
  }
}
]]

local function test_tuple_dissection()
    local recs = {
        {element = {123450, "cat", "met", "obj"}},
        {element = {123451, "cat1", "met1", "obj1", "val1"}},
        {element = {123452, "cat2", "met2", "obj2", "val2", {foo = "bar2"}}},
        {element = {123453, "cat3", "met3", "obj3",  nil, {foo = "bar3"}}},
    }
    local s =  parser.load_parquet_schema(tuple_schema)
    local w = parquet.writer("tuple.parquet", s)
    for i,v in ipairs(recs) do
        local ok, err = pcall(w.dissect_record, w, v)
        assert(ok, string.format("Test: %d err: %s", i, tostring(err)))
    end
end

test_tuple_dissection()
