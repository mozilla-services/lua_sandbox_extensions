-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local l = require "lpeg"
l.locale(l)
local pf = require "lpeg.printf"

local pre_post_re   = {"Prefix %s%s%s postfix", "@{:method: [^/ ]+ :}", "@'/'?", "@{:submethod: %S* :}"}
local pre_post_lpeg = {"Prefix %s%s%s postfix", l.Cg((1 - l.S"/ ")^1, "method"), l.P"/"^-1,
    l.Cg((1 - l.space)^0, "submethod")}

local tests = {
    {{"%i", "i"}        , "123"                     , {i = 123}},
    {{"%d", "i"}        , "123"                     , {i = 123}},
    {{"%d", "i"}        , "-123"                    , {i = -123}},
    {{"%+d", "i"}       , "+123"                    , {i = 123}},
    {{"% d", "i"}       , " 123"                    , {i = 123}},
    {{"%5d", "i"}       , "  123"                   , {i = 123}},
    {{"%05d", "i"}      , "00123"                   , {i = 123}},
    {{"%+5d", "i"}      , " +123"                   , {i = 123}},
    {{"%-+5d", "i"}     , "+123 "                   , {i = 123}},
    {{"%c", "c"}        , "c"                       , {c = "c"}},
    {{"%2c", "c"}       , " c"                      , {c = "c"}},
    {{"%s", "s"}        , "sample"                  , {s = "sample"}},
    {{"%10s", "s"}      , "    sample"              , {s = "sample"}},
    {{"%-10s", "s"}     , "sample    "              , {s = "sample"}},
    {{"%15s", "s"}      , "      sample of"         , {s = "sample of"}},
    {{"%-15s", "s"}     , "sample of      "         , {s = "sample of"}},
    {{"%s", "s"}        , "   sample of   "         , {s = "sample of"}},
    {{"%*s", "#", "s"}  , "    sample"              , {s = "sample"}},
    {{"%-*s", "#", "s"} , "sample    "              , {s = "sample"}},
    {{"%o", "i"}        , "173"                     , {i = 123}},
    {{"%x", "i"}        , "7b"                      , {i = 123}},
    {{"%#x", "i"}       , "0x7b"                    , {i = 123}},
    {{"%X", "i"}        , "7B"                      , {i = 123}},
    {{"%f", "d"}        , "12.345679"               , {d = 12.345679}},
    {{"%F", "d"}        , "12.345679"               , {d = 12.345679}},
    {{"%e", "d"}        , "1.234568e+01"            , {d = 12.34568}},
    {{"%E", "d"}        , "1.234568E+01"            , {d = 12.34568}},
    {{"%g", "d"}        , "12.3457"                 , {d = 12.3457}},
    {{"%G", "d"}        , "12.3457"                 , {d = 12.3457}},
    {{"%a", "d"}        , "0x1.8b0fcd324d5a2p+3"    , {d = 12.3456789}},
    {{"%A", "d"}        , "0X1.8B0FCD324D5A2P+3"    , {d = 12.3456789}},
    {{"%p", "p"}        , "0x7ffd436ddda0"          , {p = "0x7ffd436ddda0"}},
    {{"%n", "n"}        , ""                        , {}}, -- ignored
    {{"%%", "p"}        , "%"                       , {}}, -- literal not captured
    {{"'%s'", "s"}      , "'test'"                  , {s = "test"}},
    {{"This %s test", "s"}              , "This is a space test", {s = "is a space"}},
    {{"%5s%5s%5s", "s1", "s2", "s3"}    , "    c   c1  c11", {s1 = "c", s2 = "c1", s3 = "c11"}},
    {{"%5s %6s %7s", "s1", "s2", "s3"}    , "    a      b       c", {s1 = "a", s2 = "b", s3 = "c"}},
    {{"%-5s%-5s%-5s", "s1", "s2", "s3"} , "c    c1   c11  ", {s1 = "c", s2 = "c1", s3 = "c11"}},
    {{"%-5s %-6s %-7s", "s1", "s2", "s3"} , "a     b      c      ", {s1 = "a", s2 = "b", s3 = "c"}},
    {{"Dquote string \"%s\"", "s1"} , "Dquote string \"foo \" bar\"", {s1 = "foo \" bar"}},
    {{"Everything %d %c %g %s", "i", "c", "d", "s"} , "Everything 123 c 12.3457 sample",
        {i = 123, c = "c", d = 12.3457, s = "sample"}},
    {{"Everything together %d%c%g%s", "i", "c", "d", "s"} , "Everything together 123c12.3457sample",
        {i = 123, c = "c", d = 12.3457, s = "sample"}},
    {{"Multi string '%s' \"%s\"", "s1", "s2"} , "Multi string '1 '2' 3' \"4 \"5\" 6\"",
        {s1 = "1 '2' 3", s2 = '4 "5" 6'}},
    {{"%.3s", "s"}, "AAABBB", nil},
    {{"%5.3s", "s"}, "  AAA", {s = "AAA"}},
    {{"%.3s%.3s", "s", "t"}, "AAABBB", {s = "AAA", t = "BBB"}},
    {{"%.3s%.3s", "s", "t"}, "ABBB", {s = "ABB", t = "B"}}, -- ambigious so it is greedy
    {{"%3.3s%.3s", "s", "t"}, "  ABBB", {s = "A", t = "BBB"}},
    {{"%.3s end", "s", "t"}, "aaa end", {s = "aaa"}},
    {{"%.3s end", "s", "t"}, "a end", {s = "a"}},
    {{"%.3s end", "s", "t"}, "aaabbb end", nil},
    {{"%s", "@{:state: 'Accept' / ' Deny' :}"}  , "Accept", {state = "Accept"}},
    {{"%s", "@{:state: 'Accept' / ' Deny' :}"}  , "Fail", nil},
    {pre_post_re, "Prefix foo/bar postfix", {method = "foo", submethod = "bar"}},
    {pre_post_lpeg, "Prefix foo/bar postfix", {method = "foo", submethod = "bar"}},
    {pre_post_re, "Prefix foo/bar postfix", {method = "foo"}},
    {pre_post_lpeg, "Prefix foo/bar postfix", {method = "foo"}},
    {{"Running %s.", "s1"} , "Running foobar. ", {s1 = "foobar"}},
}


local function verify_table(idx, rt, et)
    for k,e in pairs(et) do
        local r = rt[k]
        if r ~= e then
            error(string.format("test: %d key: %s received (%s): '%s' expected: '%s'",
                                idx, k, type(r), tostring(r), tostring(e)))
        end
    end
end


for i,v in ipairs(tests) do
    local g = pf.build_grammar(v[1])
    if not g then
        error(string.format("test: %d bad grammar", i))
    end

    local r = g:match(v[2])
    local typ = type(r)
    if typ == "table" then
        verify_table(i, r, v[3])
    elseif r ~= v[3] then
        error(string.format("test: %d received: %s expected: %s", i, typ, type(v[3])))
    end
end


local test_errors = {
    {{"%Q"}, "could not parse the printf format string: %Q"},
    {{"%s %s", "one", nil}, "fmt: '%s %s' arg: 2 error: 'invalid type'"},
    {{"%s", "@{:foo"}, "fmt: '%s' arg: 1 error: 'pattern error near ':foo''"}
}


for i,v in ipairs(test_errors) do
    local ok, g = pcall(pf.build_grammar, v[1])
    if ok then
        error(string.format("test: %d should not build", i))
    end
    if g ~= v[2] then
        error(string.format("test: %d received: %s expected: %s", i, g, v[2]))
    end
end


-- test load and match
local printf_messages_err = {
    {"%d %d", "one", "two"},
    "printf_m3"
}
local ok, err = pcall(pf.load_messages, printf_messages_err)
assert(not ok)
assert(err == "module: printf_m3 item: 2 error: fmt: '%s' arg: 1 error: 'pattern error near ':foo''", err)

local printf_messages_err = {
    "printf_m4"
}
local ok, err = pcall(pf.load_messages, printf_messages_err)
assert(not ok)
assert(err == "module: printf_m4 item: 1 error: printf format must be a string", err)

local printf_messages = {
    {"%d %d", "one", "two"},
    "printf_m1"
}

local grammars = pf.load_messages(printf_messages)
assert(grammars)
assert(#grammars == 3)
assert(pf.match_sample(grammars, "1 2") == grammars[1][1])
assert(pf.match_sample(grammars, "1 2 3") == grammars[2][1])
assert(pf.match_sample(grammars, "status 1 2 3") == grammars[3][1])
assert(not pf.match_sample(grammars, "foo 1 2"))
grammars = pf.load_messages({{"%s", "string"}}, grammars, #grammars)
assert(pf.match_sample(grammars, "foo 1 2") == grammars[4][1])
