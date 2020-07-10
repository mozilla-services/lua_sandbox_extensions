-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"
require "gzfile"
assert(gzfile.version() == "0.0.2", gzfile.version())

local errors = {
    function()
        gzfile.open() --incorrect # args
    end,
    function()
        gzfile.open({}) --incorrect argument type
    end,
    function()
        gzfile.open("foo.txt", {}) --incorrect argument type
    end,
    function()
        gzfile.open("foo.txt", "rb", "s") --incorrect argument type
    end,
    function()
        local gzf = gzfile.open("uncompressed.log")
        gzf:close(1) --incorrect # args
    end,
    function()
        local gzf = gzfile.open("uncompressed.log")
        gzf:lines("foo") --incorrect argument type
    end,
}

for i, v in ipairs(errors) do
    local ok = pcall(v)
    if ok then error(string.format("error test %d failed\n", i)) end
end

local rep = "0123456789"
local uncompressed = {
    "line one\n",
    "line two\n",
    "This is a long line three that should be truncated at eighty characters 12345678 truncated\n",
    "line four no terminating new line",
}

local uncompressed_trunc = {
    "line one\n",
    "line two\n",
    "This is a long line three that should be truncated at eighty characters 12345678",
    "line four no terminating new line",
}

local compressed_trunc = {
    "line one\n",
    string.rep(rep, 8),
    "line 3\n"
}

local compressed = {
    "line one\n",
    string.rep(rep, 3000) .. "\n",
    "line 3\n"
}

local function run_test(fn, results, max_line)
    local gzf = assert(gzfile.open(fn, "rb"))
    local cnt = 0
    for line in gzf:lines(max_line) do
        cnt = cnt + 1
        if line ~= results[cnt] then
            error(string.format("line: %d received: %s expected: %s", cnt, line, results[cnt]))
        end
    end
    assert(cnt == #results, cnt)
    gzf:close()
end


local function run_string_test(fn, results)
    local s = assert(gzfile.string(fn))
    assert(s == table.concat(results))
end


local function run_string_fail(fn, err, max_bytes)
    local ok, s = pcall(gzfile.string, fn, nil, nil, max_bytes)
    if(s ~= err) then
        error(string.format("received: %s expected: %s", s, err))
    end
end

assert(not gzfile.open("foo.txt"))
run_test("uncompressed.log", uncompressed)
run_test("uncompressed.log", uncompressed_trunc, 80)
run_test("compressed.log", compressed_trunc, 80)
run_test("compressed.log", compressed, 32 * 1024)
run_string_test("compressed.log", compressed)
run_string_test("uncompressed.log", uncompressed)
run_string_fail("uncompressed.log", "max_bytes exceeded", 50)
run_string_fail("foo.txt", "open failed")
