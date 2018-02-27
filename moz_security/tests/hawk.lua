-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local hawk = require "hawk"
local string = require "string"

local function testpattern(s, p)
    assert(string.match(s, p), string.format("test: %s, expected match for %s", s, p))
end

local nppattern = "Hawk id=\"test\", ts=\"%d+\", nonce=\"%S+\", mac=\"%S+\""
local pattern = "Hawk id=\"test\", ts=\"%d+\", nonce=\"%S+\", hash=\"%S+\", mac=\"%S+\""

hawkhdr = hawk.new("test", "key", "web.host", 443)
testpattern(hawkhdr:get_header("GET", "/uri/path", nil, nil), nppattern)
testpattern(hawkhdr:get_header("POST", "/uri/path", "{}\n", "application/json"), pattern)


hawkhdr = hawk.new("test", "key", "web.host", 80)
testpattern(hawkhdr:get_header("GET", "/uri/path", nil, nil), nppattern)
testpattern(hawkhdr:get_header("POST", "/uri/path", "Testing", "test/plain"), pattern)

ok, res = pcall(hawk.new, "test", "key", "http://web.host", 80)
assert(not ok, "test: hawk.new should have failed")
ok, res = pcall(hawk.new, "test", "key", "web.host", "80")
assert(not ok, "test: hawk.new should have failed")
ok, res = pcall(hawk.new, "test", nil, "web.host", 80)
assert(not ok, "test: hawk.new should have failed")
ok, res = pcall(hawk.new, "test", "key", nil, nil)
assert(not ok, "test: hawk.new should have failed")
