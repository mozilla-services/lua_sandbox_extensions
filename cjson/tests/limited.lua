-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"
local cj = require "cjson"
local js = '["this is a test","this is a test","this is a test","this is a test","this is a test"]'

function process()
    local t = cjson.decode(js)
    assert(#t == 5, "can decode a JSON string bigger than the output buffer")

    local ok, json = pcall(cjson.encode, t)
    assert(not ok, "cannot encode an array bigger than the the output buffer")
    return 0
end

