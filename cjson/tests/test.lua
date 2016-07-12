-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"
local cj = require "cjson"
local js = '["this is a test","this is a test","this is a test","this is a test","this is a test"]'

assert(cj == cjson, "cjson not creating a global table")

local value = cjson.decode("[ true, { \"foo\": \"bar\" } ]")
assert("bar" == value[2].foo, string.format("bar: %s", tostring(value[2].foo)))

local null_json = '{"test" : 1, "null" : null}'
local value = cjson.decode(null_json)
assert(value.null == nil, "null not discarded")

cjson.decode_null(true)
value = cjson.decode(null_json)
assert(type(value.null) == "userdata", "null discarded")

assert(not cjson.new)

assert(not cjson.encode_keep_buffer)
