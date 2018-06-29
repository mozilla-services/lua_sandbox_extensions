-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local es = require "lpeg.escape_sequences"

assert(es.hex_to_utf8("0024") == "\36")
assert(es.hex_to_utf8("00A2") == "\194\162")
assert(es.hex_to_utf8("20AC") == "\226\130\172")
assert(es.hex_to_utf8("00010348") == "\240\144\141\136")
assert(es.hex_to_utf8("ffffffff") == "\239\191\189")
assert(es.hex_to_char("28") == "(")
assert(es.octal_to_char("50") == "(")

local c_tests = {
    {"\\a", "\a"},
    {"\\b", "\b"},
    {"\\e", "\27"},
    {"\\f", "\f"},
    {"\\n", "\n"},
    {"\\r", "\r"},
    {"\\t", "\t"},
    {"\\v", "\v"},
    {"\\\\", "\\"},
    {"\\'", "'"},
    {'\\"', '"'},
    {"\\?", "?"},
    {"\\u0024", "\36"},
    {"\\u00a2", "\194\162"},
    {"\\u20ac", "\226\130\172"},
    {"\\U00010348", "\240\144\141\136"},
    {"\\Uffffffff", "\239\191\189"},
    {"\\50", "("},
    {"\\x28", "("},
    {"\\xF", "\15"},
}

for i,v in ipairs(c_tests) do
    local r = es.c:match(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end


local json_tests = {
    {"\\b", "\b"},
    {"\\f", "\f"},
    {"\\n", "\n"},
    {"\\r", "\r"},
    {"\\t", "\t"},
    {"\\\\", "\\"},
    {"\\/", "/"},
    {'\\"', '"'},
    {"\\u0024", "\36"},
    {"\\u00a2", "\194\162"},
    {"\\u20ac", "\226\130\172"},
}

for i,v in ipairs(json_tests) do
    local r = es.json:match(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end


local escape_json_tests = {
    {"\0", "\\u0000"},
    {"\b", "\\b"},
    {"\f", "\\f"},
    {"\n", "\\n"},
    {"\r", "\\r"},
    {"\t", "\\t"},
    {"\\", "\\\\"},
    {"/", "\\/"},
    {'"', '\\"'},
    {"foo\tbar", "foo\\tbar"},
}

for i,v in ipairs(escape_json_tests) do
    local r = es.escape_json(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end


local escape_html_tests = {
    {"\0", "&#0;"},
    {"\b", "&#8;"},
    {"&", "&amp;"},
    {"<", "&lt;"},
    {">", "&gt;"},
    {'"', "&quot;"},
    {"'", "&apos;"},
    {"`", "&grave;"},
    {"!", "&excl;"},
    {"@", "&copy;"},
    {"$", "&dollar;"},
    {"%", "&percnt;"},
    {"(", "&lpar;"},
    {")", "&rpar;"},
    {"=", "&equals;"},
    {"+", "&plus;"},
    {"{", "&lcub;"},
    {"}", "&rcub;"},
    {"[", "&lsqb;"},
    {"]", "&rsqb;"},
    {"foo+bar", "foo&plus;bar"},
}

for i,v in ipairs(escape_html_tests) do
    local r = es.escape_html(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end


local percent_tests = {
    {"%26", "&"},
}

for i,v in ipairs(percent_tests) do
    local r = es.percent:match(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end

local url_tests = {
    {"%26", "&"},
    {"+", " "},
}

for i,v in ipairs(url_tests) do
    local r = es.url:match(v[1])
    assert(r == v[2], string.format("failed test: %d expected: '%s' received: '%s'", i, v[2], tostring(r)))
end
