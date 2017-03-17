# RapidJSON Lua Module

## Overview
Lua wrapper for the RapidJSON library allowing for JSON-Schema validation
and more efficient manipulation of large JSON structures where only a small
amount of the data is consumed within the Lua script.  Schema pattern matching
is restricted to a subset of regex described in the *Regular Expression* section
of the [RapidJSON Schema Documentation](http://rapidjson.org/md_doc_schema.html).

## Module

### Example Usage
```lua
require "rjson"

json = [[{"array":[1,"string",true,false,[3,4],{"foo":"bar"},null]}]]
doc = rjson.parse(json)
str = doc:find("array", 1);
-- str == "string"
```

### Functions

#### parse

Creates a JSON Document from a string.

```lua
local ok, doc = pcall(rjson.parse, '{"foo":"bar"}')
assert(ok, doc)

```
*Arguments*
* JSON (string) - JSON string to parse
* validate_encoding (bool, default: false) - true to turn on UTF-8 validation

*Return*
* doc (userdata) - JSON document or an error is thrown

#### parse_schema

Creates a JSON Schema.

```lua
local ok, doc = pcall(rjson.parse_schema, '{"type":"array","minItems": 1,"oneOf": [{"items": {"type":"number"}}]}')
assert(ok, doc)

```
*Arguments*
* JSON (string) - JSON schema string to parse

*Return*
* schema (userdata) - JSON schema or an error is thrown

#### parse_message (Heka sandbox only)

Creates a JSON Document from a message variable.

```lua
local ok, doc = pcall(rjson.parse_message, "Fields[myjson]")
assert(ok, doc)

```
*Arguments*
* heka_stream_reader (userdata) - require only for Input plugins since there is
  no active message available.
* variableName (string)
    * Payload
    * Fields[*name*]
* fieldIndex (unsigned) - optional, only used in combination with the Fields
  variableName use to retrieve a specific instance of a repeated field name;
  zero indexed
* arrayIndex (unsigned) - optional, only used in combination with the Fields
  variableName use to retrieve a specific element out of a field containing an
  array; zero indexed
* validate_encoding (bool, default: false) - true to turn on UTF-8 validation

*Return*
* doc (userdata) - JSON document or an error is thrown

#### version
```lua
require "rjson"
local v = rjson.version()
-- v == "1.0.0"
```

Returns a string with the running version of rjson.

*Arguments*
- none

*Return*
- Semantic version string

### JSON Document Methods

#### parse
#### parse_message (Heka sandbox only)
Re-uses the document object to avoid GC costs/lag. Same arguments/returns as the
rjson functions.

#### validate

Checks that the JSON document conforms to the specified schema.

```lua
local ok, err = doc:validate(schema)
assert(ok, err)

```
*Arguments*
* heka_schema (userdata) - a compiled schema to validate against

*Return*
* ok (bool) - true if valid
* err (string) - error message on failure

#### find

Searches for and returns a value in the JSON structure.

```lua
local v = doc:find("obj", "arr", 0, "foo")
assert(v, "not found")

```
*Arguments*
* value (lightuserdata) - optional, when not specified the function is applied
  to document
* key (string, number) - object key, or array index
* keyN (string, number) - final object key, or array index

*Return*
* value (lightuserdata) - handle to be passed to other methods, nil if not found

#### remove

Searches for and removes the resulting value in the JSON structure returning
the removed value in new document (full copy).

```lua
local rv = doc:remove("obj", "arr")
assert(rv, "not found")
rv:size() -- number of elements in the extracted array

```
*Arguments*
* value (lightuserdata) - optional, when not specified the function is applied
  to document
* key (string, number) - object key, or array index
* keyN (string, number) - final object key, or array index

*Return*
* doc (userdata) - new document containing the removed value or nil

#### remove_shallow

Searches for and removes the resulting value in the JSON structure returning
a reference to extracted JSON value (shallow copy).

```lua
local rv = doc:remove_shallow("obj", "arr")
assert(rv, "not found")
doc:size(rv) -- number of elements in the extracted array

```
*Arguments*
* value (lightuserdata) - optional, when not specified the function is applied
  to document
* key (string, number) - object key, or array index
* keyN (string, number) - final object key, or array index

*Return*
* value (lightuserdata) - value reference or nil

#### value

Returns the primitive value of the JSON element.

```lua
local v = doc:find("obj", "arr", 0, "foo")
local str = doc:value(v)
assert("bar" == str, tostring(str))

```
*Arguments*
* value (lightuserdata, nil) - optional, when not specified the function is
  applied to document (accepts nil for easier nesting without having to test the
  inner expression) e.g., str = doc:value(doc:find("foo")) or "my default"

*Return*
* primitive - string, number, bool, nil or throws an error if not convertible
  (object, array)

#### type

Returns the type of the value in the JSON structure.

```lua
local t = doc:type()
assert(t == "object", t)

```
*Arguments*
* value (lightuserdata, nil) - optional, when not specified the function is
  applied to document (accepts nil for easier nesting without having to test the
  inner expression)

*Return*
* type (string, nil) - "string", "number", "boolean", "object", "array" or
  "null"

#### iter

Retrieves an iterator function for an object/array.

```lua
local v = doc:find("obj", "arr")
for i,v in doc:iter(v) do
-- ...
end
```
*Arguments*
* value (lightuserdata, nil) - optional, when not specified the function is
  applied to document (accepts nil for API consistency)

*Return*
* iter (function, nil) - iterator function returning an index/value for arrays
  or a key/value for objects.  Throws an error on primitive types.

#### size

Returns the size of the value.
```lua
local v = doc:find("obj", "arr")
local n = doc:size(v)

```
*Arguments*
* value (lightuserdata, nil) - optional, when not specified the function is
  applied to document (accepts nil for easier nesting without having to test the
  inner expression)

*Return*
* size (number, nil) - Number of element in an array/object or the length of the
  string. Throws an error on numeric, boolean and null types.

#### make_field (Heka sandbox only)

Helper function to wrap the lightuserdata so it can be used in a Heka
inject_message field).

```lua
local msg = {Fields = {}}
local v = doc:find("obj", "arr")
msg.Fields.array = doc:make_field(v)  -- set array to the JSON string representation of "arr"
inject_message(msg)

```
*Arguments*
* value (lightuserdata, nil) - optional, when not specified the function is
  applied to document (accepts nil for easier nesting without having to test the
  inner expression)

*Return*
* field (table, nil) - i.e., `{value = v, userdata = doc, representation = "json"}`
