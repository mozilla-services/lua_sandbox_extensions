-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local lf = require "lpeg.logfmt"

local tests = {
    {[[foo=bar a=14 baz="hello kitty" cool%story=bro f %^asdf escaped="\"\\\u0041 test item\\\""]],
        {foo = "bar",  a = "14",  baz = "hello kitty",  ["cool%story"] = "bro",  f = true,  ["%^asdf"] = true,
            escaped = '"\\A test item\\"'}
    },
}


local function verify_output(i, result, expect)
    for k,v in pairs(expect) do
        if v ~= result[k] then
            error(string.format("test: %d key: %s expected: '%s' received: '%s'",
                          i, k, tostring(v), tostring(result[k])))
        end
    end
end


local function test_grammar()
    for i,v in ipairs(tests) do
        local r = lf.grammar:match(v[1])
        verify_output(i, r, v[2])
    end
end

test_grammar()
