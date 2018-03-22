-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "rjson"
assert(rjson.version() == "1.1.3", rjson.version())

schema_json = [[{
    "type":"object",
    "required":["Timestamp"],
    "properties":{
        "Timestamp":{
            "type":"integer",
            "minimum":0
        },
        "Type":{
            "type":"string"
        },
        "Logger":{
            "type":"string"
        },
        "Hostname":{
            "type":"string",
            "format":"hostname"
        },
        "EnvVersion":{
            "type":"string",
            "pattern":"^\\d+(\\.[0-9]+){0,2}"
        },
        "Severity":{
            "type":"integer",
            "minimum":0,
            "maximum":7
        },
        "Pid":{
            "type":"integer",
            "minimum":0
        },
        "Fields":{
            "type":"object",
            "minProperties":1,
            "additionalProperties":{
                "anyOf": [
                    { "$ref": "#/definitions/field_value"},
                    { "$ref": "#/definitions/field_array"},
                    { "$ref": "#/definitions/field_object"}
                ]
            }
        }
    },
    "definitions":{
        "field_value":{
            "type":["string", "number", "boolean"]
        },
        "field_array":{
            "type":"array",
            "minItems": 1,
            "oneOf": [
                    {"items": {"type":"string"}},
                    {"items": {"type":"number"}},
                    {"items": {"type":"boolean"}}
            ]
        },
        "field_object":{
            "type":"object",
            "required":["value"],
            "properties":{
                "value":{
                    "oneOf": [
                        { "$ref": "#/definitions/field_value" },
                        { "$ref": "#/definitions/field_array" }
                    ]
                },
                "representation":{"type":"string"}
            }
        }
    }
}]]

json = [[{"Timestamp":0, "Type":"foo", "Logger":"bar"}]]

schema = rjson.parse_schema(schema_json)
assert(schema)

ok, err = pcall(rjson.parse_schema, "{")
assert(not ok)
assert(err == "failed to parse offset:1 Missing a name for object member.", err)
ok, err = pcall(rjson.parse, "{")
assert(not ok)
assert(err == "failed to parse offset:1 Missing a name for object member.", err)

doc = rjson.parse(json)
assert(doc)
ok, err = doc:validate(schema)
assert(ok and type(ok) == "boolean" and err == nil)
doc1 = rjson.parse(json)

json = [[{"Timestamp":-1, "Type":"foo", "Logger":"bar"}]]
doc = rjson.parse(json)
assert(doc)
assert(not doc:validate(schema))

json = [[{"Timestamp":0, "EnvVersion":"unknown"}]]
doc = rjson.parse(json)
assert(doc)
assert(not doc:validate(schema))

json = [[{"array":[1,"string",true,false,[3,4],{"foo":"bar"},null]}]]
doc = rjson.parse(json)
assert(doc)
assert(doc:type() == "object")
a = doc:find("array");
assert(doc:type(a) == "array")
str = doc:find(a, 1)
assert("string" == doc:type(str), doc:type(str))
tmp = doc:find("array", 3);
assert("boolean" == doc:type(tmp), doc:type(tmp))
ok, err = pcall(doc.iter, doc, tmp)
assert("iter() not allowed on a primitive type", err, err)
ok, err = pcall(doc.find, doc, doc1, "array")
assert("invalid value" == err, err)
tmp = doc:find("array", "key")
assert(not tmp)
tmp = doc:find("array", 5, 0)
assert(not tmp)
tmp = doc:find("array", 7)
assert(not tmp)
tmp = doc:find(true)
assert(not tmp)
tmp = doc:find("array", 5, "missing")
assert(not tmp)

ra = {
    {value = 1, type = "number"},
    {value = "string", type = "string", len = 6},
    {value = true, type = "boolean"},
    {value = false, type = "boolean"},
    {type = "array", len = 2},
    {type = "object", len = 1},
    {type = "null"},
}

for i,v in doc:iter(a) do
    assert(ra[i+1].type == doc:type(v))
    if ra[i+1].value ~= nil then
        assert(ra[i+1].value == doc:value(v))
    else
        ok, err = pcall(doc.value, doc, v)
        if ra[i+1].type == "null" then
            assert(ok)
        else
            assert(not ok)
        end
    end
    if ra[i+1].len then
        assert(ra[i+1].len == doc:size(v))
    else
        ok, err = pcall(doc.size, doc, v)
        assert(not ok)
    end
end

a0 = doc:find("array", 0);
assert(a0)
assert(doc:value(a0) == 1)

a5 = doc:find("array", 5);
assert(a5)
assert(doc:type(a5) == "object")
assert(doc:size(a5) == 1)
for k,v in doc:iter(a5) do
    assert(doc:type(v) == "string")
    assert(doc:value(v) == "bar")
    assert(k == "foo", tostring(k))
end

a5x = doc:find("array", 5);
assert(a5 == a5x)

ok, doc = pcall(rjson.parse, "{\"foo\":\"bar\"}")
assert(ok, doc)

foo = doc:find("foo")
assert(foo)
assert("bar" == doc:value(foo), tostring(doc:value(foo)))
ok, err = pcall(doc.value, doc, (doc1:find()))
assert(not ok)
assert("invalid value" == err, err)

assert("object" == doc:type(), doc:type());
assert(doc:size() == 1, doc:size())
ok, err = pcall(doc.remove, doc)
assert(err == "cannot remove the root", err)
rdoc = doc:remove("foo")
assert("object" == doc:type(), doc:type());
assert(doc:size() == 0, doc:size())
assert("bar" == rdoc:value(), tostring(rdoc:value()))

assert("string" == rdoc:type(), rdoc:type());
nrdoc = rdoc:remove("foo")
assert("string" == rdoc:type(), rdoc:type());

ok, doc = pcall(rjson.parse, "{\"foo\":\"bar\"}")
assert(ok, doc)
assert("object" == doc:type(), doc:type());
assert(doc:size() == 1, doc:size())
rdoc = doc:remove_shallow("foo")
assert("object" == doc:type(), doc:type());
assert(doc:size() == 0, doc:size())
ok, err = pcall(doc.remove, doc, rdoc)
assert(err == "cannot remove the root", err)
assert("bar" == doc:value(rdoc), tostring(doc:value(rdoc)))

nested = '{"main":{"m1":1}, "payload":{"values":[1,2,3]}}'
json = rjson.parse(nested)
assert(json)
assert(json:size() == 2, json:size())
values = json:find("payload", "values")
assert(values)
vit = json:iter(values)
i,v = vit()
assert(i == 0, tostring(i))
assert(json:value(v) == 1, tostring(json:value(v)))
i,v = vit()
json:remove("payload")
assert(i == 1, tostring(i))
assert(json:value(v) == 2, tostring(json:value(v)))
i,v = vit()
assert(i == 2, tostring(i))
assert(json:value(v) == 3, tostring(json:value(v)))
i,v = vit()
assert(i == nil, tostring(i))

json = rjson.parse(nested)
assert(json)
object = json:find("main")
vit = json:iter(object)
json:remove("main")
ok, err = pcall(vit)
assert(err == "iterator has been invalidated")

json = rjson.parse(nested)
assert(json)
values = json:find("payload", "values")
vit = json:iter(values)
rvalues = json:remove("payload", "values")
assert(2 == rvalues:value(rvalues:find(1)))
ok, err = pcall(vit)
assert(err == "iterator has been invalidated")
schema_array = [[{
"type":"array",
"minItems": 1,
"oneOf": [{"items": {"type":"number"}}]
}]]
sa = rjson.parse_schema(schema_array)
assert(sa)
assert(rvalues:validate(sa))

json = json:parse(nested) -- re-use the object
assert(json)
assert(json:size() == 2, json:size())
assert(2 == rvalues:value(rvalues:find(1))) -- use an object extracted from the old doc

assert(nil == doc:find(nil))
assert(nil == doc:find(nil))
assert(nil == doc:size(nil))
assert(nil == doc:type(nil))
assert(nil == doc:iter(nil))

json = '{"f\240o":"bar"}'
ok, err = pcall(rjson.parse, json)
assert(ok, err)
ok, err = pcall(rjson.parse, json, true)
assert(not ok, "UTF-8 validation failed")

doc = rjson.parse(nested)
assert(doc)
ok, err = pcall(doc.parse, doc, "{")
assert(not ok) -- doc is now Null
assert(nil == doc:find("main", "m1"))
