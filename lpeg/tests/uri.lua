-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local uri = require "lpeg.uri"
require "string"

function verify_fields(expected, received, id, symmetric)
    for k,e in pairs(expected) do
        local r = received[k]
        if e ~= r then
            error(string.format("test: %d field: %s expected: %s received: %s", id, k, e, tostring(r)))
        end
    end
    if symmetric then
        verify_fields(received, expected, -id)
    end
end


local function uri_tests()
    local tests = { -- uri, result
        {"ftp://ftp.is.co.za/rfc/rfc1808.txt", {scheme="ftp",host="ftp.is.co.za",path="/rfc/rfc1808.txt"}},
        {"http://www.ietf.org/rfc/rfc2396.txt", {scheme="http",host="www.ietf.org",path="/rfc/rfc2396.txt"}},
        {"http://www.ietf.org/rfc/rfc+2396.txt", {scheme="http",host="www.ietf.org",path="/rfc/rfc+2396.txt"}},
        {"http://www.ietf.org/rfc/rfc%202396.txt", {scheme="http",host="www.ietf.org",path="/rfc/rfc 2396.txt"}},
        {"ldap://[2001:db8::7]/c=GB?objectClass?one", {scheme="ldap",host="2001:db8::7",path="/c=GB",query="objectClass?one"}},
        {"ldap://[2001:db8::7]/c=GB?object+Class?%23%26%3Bone", {scheme="ldap",host="2001:db8::7",path="/c=GB",query="object+Class?%23%26%3Bone"}},
        {"mailto:John.Doe@example.com", {scheme="mailto",path="John.Doe@example.com"}},
        {"news:comp.infosystems.www.servers.unix", {scheme="news",path="comp.infosystems.www.servers.unix"}},
        {"tel:+1-816-555-1212", {scheme="tel",path="+1-816-555-1212"}},
        {"telnet://192.0.2.16:80/", {scheme="telnet",host="192.0.2.16",port="80",path="/"}},
        {"urn:oasis:names:specification:docbook:dtd:xml:4.1.2", {scheme="urn",path="oasis:names:specification:docbook:dtd:xml:4.1.2"}},
        {"foo://example.com:8042/over/there?name=ferret#nose",
            {scheme="foo",host="example.com",port="8042",path="/over/there",query="name=ferret",fragment="nose"}},
        {"absolute:/foo", {scheme="absolute",path="/foo"}},
        {"rootless:foo", {scheme="rootless",path="foo"}},
        {"empty:", {scheme="empty"}},
    }

    for i, v in ipairs(tests) do
        local fields = uri.uri:match(v[1])
        if not fields then
            error(string.format("test: %s failed to match: %s", i, v[1]))
        end
        verify_fields(v[2], fields, i, true)
    end

    local errors = {
        "telnet://192.0.2.256:80/",
        "test.html?foo=bar",
    }

    for i, v in ipairs(errors) do
        local fields = uri.uri:match(v)
        if fields then
            error(string.format("test: %s incorrectly matched: %s", i, v))
        end
    end
end


local function uri_reference_tests()
    local tests = { -- uri, result
        {"http://www.ietf.org/rfc/rfc2396.txt", {scheme="http",host="www.ietf.org",path="/rfc/rfc2396.txt"}},
        {"test.html?foo=bar", {path="test.html",query="foo=bar"}},
        {"../../test.html", {path="../../test.html"}},
        {"//192.0.2.16:80", {host="192.0.2.16",port="80",path=""}},
        {"/absolute", {path="/absolute"}},
        {"noscheme?foo=bar#frag", {path="noscheme",query="foo=bar",fragment="frag"}},
        {"?foo=bar#frag", {query="foo=bar",fragment="frag"}},
        {"#frag", {fragment="frag"}},
    }

    for i, v in ipairs(tests) do
        local fields = uri.uri_reference:match(v[1])
        if not fields then
            error(string.format("test: %s failed to match: %s", i, v[1]))
        end
        verify_fields(v[2], fields, i, true)
    end

    local errors = {
        "",
        ":foo",
    }

    for i, v in ipairs(errors) do
        local fields = uri.uri:match(v)
        if fields then
            error(string.format("test: %s incorrectly matched: %s", i, v))
        end
    end
end


local function url_query_tests()
    local tests = { -- query string, result
        {"foo", {foo = ""}},
        {"foo&bar&widget", {foo = "", bar = "", widget = ""}},
        {"foo=", {foo = ""}},
        {"foo=bar", {foo = "bar"}},
        {"foo=bar&widget=8", {foo = "bar", widget = "8"}},
        {"v=test%20value&arg=%40%40+%26%3B%40", {v = "test value", arg = "@@ &;@"}},
        {"foo%20bar=value", {["foo bar"] = "value"}},
        {"foo+bar=test+value", {["foo bar"] = "test value"}},
        {"v=1&&&&&&&&w=2", {v = "1", w = "2"}},
        {"v===2", {v = "==2"}},
        {"", {}},
    }

    for i, v in ipairs(tests) do
        local fields = uri.url_query:match(v[1])
        if not fields then
            error(string.format("test: %s failed to match: %s", i, v[1]))
        end
        verify_fields(v[2], fields, i, true)
    end

    local errors = {
        "=",
        "&",
    }

    for i, v in ipairs(errors) do
        local fields = uri.url_query:match(v)
        if fields then
            error(string.format("test: %s incorrectly matched: %s", i, v))
        end
    end
end

uri_tests()
uri_reference_tests()
url_query_tests()
