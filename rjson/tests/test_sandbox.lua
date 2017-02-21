-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "rjson"

ok, doc = pcall(rjson.parse_message)
assert("bad argument #0 to '?' (invalid number of arguments)" == doc, doc)

ok, doc = pcall(rjson.parse_message, "", "Fields[json]")
assert("bad argument #1 to '?' (lsb.heka_stream_reader expected, got string)" == doc, doc)

hsr = create_stream_reader("test")
hsr:decode_message("\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\4\82\23\10\4\106\115\111\110\16\1\42\13\123\34\102\111\111\34\58\34\98\97\114\34\125")
ok, doc = pcall(rjson.parse_message, hsr, "Fields[missing]")
assert("field not found" == doc, doc)

ok, doc = pcall(rjson.parse_message, hsr, "Fields[missing]", "")
assert("bad argument #3 to '?' (number expected, got string)" == doc, doc)

ok, doc = pcall(rjson.parse_message, hsr, "Fields[missing]", 0, "")
assert("bad argument #4 to '?' (number expected, got string)" == doc, doc)

ok, err = pcall(rjson.parse_message, hsr, "Fields[json")
assert("field not found" == err, err)

ok, err = pcall(rjson.parse_message, hsr, "Fieldsjson]")
assert("field not found" ==  err, err)

ok, err = pcall(rjson.parse_message, hsr, "foo")
assert("field not found" == err, err)

ok, doc = pcall(rjson.parse_message, hsr, "Fields[json]")
assert(ok, doc)

ok, doc = pcall(rjson.parse_message, hsr, "Fields[json]", nil, nil, true)
assert(ok, doc)

hsr:decode_message("\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\4\82\23\10\4\106\115\111\110\16\1\42\13\123\34\102\246\111\34\58\34\98\97\114\34\125")
ok, doc = pcall(rjson.parse_message, hsr, "Fields[json]")
assert(ok, doc)
ok, doc = pcall(rjson.parse_message, hsr, "Fields[json]", nil, nil, true)
assert(doc == "failed to parse offset:3 Invalid encoding in string.")

if read_config("have_zlib") then
    gz_nested = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\99\50\66\31\139\8\0\0\0\0\0\0\3\171\86\202\77\204\204\83\178\170\86\202\53\84\178\50\172\213\81\80\42\72\172\204\201\79\76\1\137\149\37\230\148\166\22\43\89\69\27\234\24\233\24\199\214\214\114\1\0\64\251\6\210\48\0\0\0"
    hsr:decode_message(gz_nested)
    ok, json = pcall(rjson.parse_message, hsr, "Payload")
    assert(ok, json)
    values = json:find("payload", "values")
    assert(values)

    ok, json = pcall(rjson.parse_message, hsr, "Payload", nil, nil, true)
    assert(ok, json)
    values = json:find("payload", "values")
    assert(values)

    hsr:decode_message("\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\99\50\33\031\139\008\000\000\000\000\000\000\003\171\086\074\251\150\175\100\165\148\148\088\164\084\011\000\204\086\149\195\013\000\000\000")
    ok, json = pcall(rjson.parse_message, hsr, "Payload")
    assert(ok, json)
    ok, json = pcall(rjson.parse_message, hsr, "Payload", nil, nil, true)
    assert(json == "failed to parse offset:3 Invalid encoding in string.", json)

    gz_too_large = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\99\50\51\31\139\8\0\0\0\0\0\0\3\237\193\49\13\0\0\8\3\176\31\25\147\129\178\201\71\7\73\219\52\155\2\0\0\0\0\0\0\0\0\255\100\14\116\172\116\102\0\36\0\0"
    hsr:decode_message(gz_too_large)
    ok, json = pcall(rjson.parse_message, hsr, "Payload")
    assert("ungzip failed" == json,  json)

    gz_corrupt = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\99\50\66\31\139foobar\0\3\171\86\202\77\204\204\83\178\170\86\202\53\84\178\50\172\213\81\80\42\72\172\204\201\79\76\1\137\149\37\230\148\166\22\43\89\69\27\234\24\233\24\199\214\214\114\1\0\64\251\6\210\48\0\0\0"
    hsr:decode_message(gz_corrupt)
    ok, json = pcall(rjson.parse_message, hsr, "Payload")
    assert("ungzip failed" == json,  json)
end

minimal = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\0"
hsr:decode_message(minimal)
ok, err = pcall(rjson.parse_message, hsr, "Payload")
assert("field not found" == err, err)

invalid_json = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\0\50\001{"
hsr:decode_message(invalid_json)
ok, err = pcall(rjson.parse_message, hsr, "Payload")
assert("failed to parse offset:1 Missing a name for object member." == err, err)

short_json = "\10\16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\16\0\50\1\57"
hsr:decode_message(short_json)
ok, doc = pcall(rjson.parse_message, hsr, "Payload")
assert(ok, doc)
assert("number" == doc:type(), doc:type())
assert(9 == doc:value(), tostring(doc:value()))
rv = doc:remove("foo")
assert(not rv)

assert(nil == doc:make_field(nil))
