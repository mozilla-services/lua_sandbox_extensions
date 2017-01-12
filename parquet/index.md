# Parquet Lua Module

## Overview
Lua wrapper for the parquet-cpp library allowing for Parquet file output.

## Module

### Example Usage

```lua
require "parquet"

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
writer:write_rowgroup() -- writes out the first row group
                        -- normally one would just close at the end (writing out
                        -- a single row group)
writer:dissect_record(r2)
writer:close() -- writes out a second row group with the remaining record

```

### Functions

#### schema

Creates a parquet schema for the writer.

```lua
local doc = parquet.schema("Document", hive_compatible)
```

*Arguments*
* name (string) - Parquet schema name
* hive_compatible (bool, nil/none default: false) - When true the Parquet
  column names are coverted to snake case (alphanumeric and underscore only)

*Return*
* schema (userdata) or an error is thrown

#### writer

Creates a Parquet writer.

```lua
local writer = parque.writer("foo.parquet", schema, properties)
```

*Arguments*
* filename (string) - Filename of the output
* schema (userdata) - Parquet schema
* properties (table, nil/none) - Writer properties
    ```lua
    {
        enable_dictionary = bool,
        dictionary_pagesize_limit = int64,
        write_batch_size = int64,
        data_pagesize = int64,
        version = string, -- ("1.0", "2.0")
        created_by = string,
        encoding = string, -- ("plain", "plain_dictionary", "rle", "bit_packed", "delta_binary_packed",
                           -- "delta_length_byte_array", "delta_byte_array", "rle_dictionary")
        compression = string, -- ("uncompressed", "snappy", "gzip", "lzo", "brotli")
        enable_statistics = bool,

        columns = {
            col_name1 = {
                enable_dictionary = bool,
                encoding = string,
                compression = string,
                enable_statistics = bool
            },
            ["col.nested.nameN"] = {}
        }
    }
    ```

*Return*
* writer (userdata) or an error is thrown

#### version

Returns a string with the running version of the Parquet module.

```lua
require "parquet"
local v = parquet.version()
-- v == "0.0.5"
```

*Arguments*
- none

*Return*
- Semantic version string

### Schema/Group Methods

#### add_group

Adds a structure to the schema.

```lua
local links = doc:add_group("Links", "optional", logical)
```

*Arguments*
* name (string)
* repetition ("required", "optional", "repeated")
* logical_type (string, nil/none default: "none") - see add_column for the full
  list

*Return*
* group (userdata) or throws an error

#### add_column

Adds a data column to the schema.

```lua
doc:add_column("DocId", "required", "int64", logical, flba_len, precision, scale)
```

*Arguments*
* name (string)
* repetition (string) - "requried", "optional", "repeated"
* data_type (string) - "boolean", "int32", "int64", "int96", "float", "double",
  "binary", "fixed_len_byte_array"
* logical_type (string, nil/none default: "none") - "none", "utf8", "map",
  "list", "enum", "decimal", "date", "time_millis", "time_micros",
  "timestamp_millis", "timestamp_micros", "uint_8", "uint_16", "uint_32",
  "uint_64", "int_8", "int_16", "int_32", "int_64", "json", "bson", "interval"
  see: [LogicalTypes](https://github.com/apache/parquet-format/blob/master/LogicalTypes.md)
  (MAP_KEY_VALUE is no longer used)
* flba_len (int, nil/none) - fixed length byte array length
* precision (int, nil/none) - decimal precision
* scale (int, nil/none) - decimal scale

*Return*
* none

### Schema Methods

#### finalize

Builds the schema structure after it has been completely defined. The schema
must be finalized before it is passed to the writer. Also, once the schema is
finalized it cannot be modified (an error will be thrown).

```lua
doc:finalize()
```

*Arguments*
* none

*Return*
* none or throws an error


### Writer Methods

#### dissect_record

Dissects a record into columns based on the schema.

```lua
writer:dissect_record(record)
```

*Arguments*
* record (table) - structure matching the schema

*Return*
* none or throws an error if the structure does not match the schema (fields
  that exist in the record but are not specified in the schema are ignored)

#### dissect_message (Heka sandbox only)

Dissects a message into columns based on the schema.

```lua
writer:dissect_message()
```

*Arguments*
* none

*Return*
* none or throws an error if the structure does not match the schema (fields
  that exist in the record but are not specified in the schema are ignored)


#### write_rowgroup

Writes the currently collected data out as a row group.

```lua
writer:write_rowgroup()
```

*Arguments*
* none

*Return*
* none or throws an error if the write fails


#### close

Closes the writer flushing any remaining data in the rowgroup.

```lua
writer:close()
```

*Arguments*
* none

*Return*
* none or throws an error on failure
