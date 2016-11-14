-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Parquet Schema Parser/Loader

### Example Usage
```lua
require "parquet"
local parser = require "lpeg.parquet"

local example_schema = [=[
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
]=]

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

local doc = parser.load_parquet_schema(example_schema)
local writer = parquet.writer("example.parquet", doc)
writer:dissect_record(r1)
writer:dissect_record(r2)
writer:close()

```

### Example Schema with Additional Attributes
```
message one_of_each {
  required boolean b;
  required int32 i32;
  required int32 i32ps (DECIMAL(3,2));
  required int64 i64;
  required int96 i96;
  required float f;
  required double d;
  required binary ba = 8;
  required fixed_len_byte_array(5) flba;
}
```

## Functions

### load_parquet_schema

Constructs a parquet schema from the Parquet schema specification.

*Arguments*
- spec (string) Parquet schema spec

*Return*
- schema (userdata) or an error is thrown

--]]

-- Imports
local string    = require "string"
local parquet   = require "parquet"
local l         = require "lpeg"
l.locale(l)

local error = error

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local osp        = l.space^0
local sp         = l.space^1
local repetition = l.Cg(l.P"required" + "optional" + "repeated", "repetition")

local flba_len   = l.P"(" * l.Cg(l.digit^1, "flba_len") * l.P")"
local dt_flba    = l.Cg(l.P"fixed_len_byte_array", "data_type") * flba_len
local data_types = l.P"boolean" + "int32" + "int64" + "int96" + "float" + "double" + "binary"
local data_type  = l.Cg(data_types, "data_type") + dt_flba

local precision     = l.Cg(l.digit^1, "precision")
local scale         = l.Cg(l.digit^1, "scale")
local logical_types = (l.P"NONE" + "UTF8" + "MAP" + "MAP_KEY_VALUE" + "LIST"
+ "ENUM" + "DATE" + "TIME_MILLIS" + "TIME_MICROS" + "TIMESTAMP_MILLIS"
+ "TIMESTAMP_MICROS" + "UINT_8" + "UINT_16" + "UINT_32" + "UINT_64" + "INT_8"
+ "INT_16" + "INT_32" + "INT_64" + "JSON" + "BSON" + "INTERVAL") / string.lower
local lt_decimal    = l.Cg(l.P"DECIMAL" / string.lower, "logical_type") * "(" * precision * "," * scale * ")"
local logical_type  = l.P"(" * (l.Cg(logical_types, "logical_type") + lt_decimal) * l.P")"
local id = osp * "=" * osp * l.digit^1 * osp

local name      = l.Cg((l.alnum + "_")^1, "name")
local column    = osp * l.Ct(repetition * sp * data_type * sp * name * (sp * logical_type)^-1) * id^-1 * l.P";" * osp

-- the data_type/logical_type combinations will be verified during load and don't need to be duplicated here
local grammar = l.P{"message"; -- intitial rule name
    message = osp * l.Ct(l.P"message" * sp * name * sp * "{" * l.V"fields" * "}") * osp,
    group  = osp * l.Ct(repetition * sp * "group" * sp * name * (sp * logical_type)^-1 * osp * "{" * l.Cg(l.Ct(l.V"fields"), "fields") * "}") * osp,
    fields = l.Cg((l.V"group" + column)^1),
}


local function load_fields(spec, parent)
    for i = 1, #spec do
        local s = spec[i]
        if s.fields then
            local np = parent:add_group(s.name, s.repetition, s.logical_type)
            load_fields(s.fields, np)
        else
            parent:add_column(s.name, s.repetition, s.data_type, s.logical_type,
                              s.flba_len, s.precision, s.scale)
        end
    end
end


function load_parquet_schema(spec)
    local ps = grammar:match(spec)
    if not ps then error"failed parsing the spec" end
    local root = parquet.schema(ps.name)
    load_fields(ps, root)
    root:finalize()
    return root
end

return M


