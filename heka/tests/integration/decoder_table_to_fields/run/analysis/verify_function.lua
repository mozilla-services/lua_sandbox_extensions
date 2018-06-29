-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for heka table_to_fields decoder
--]]

require "string"
local test = require "test_verify_message"

local messages = {
    {
        Type = "default_header",
        Fields = {
            foo = "bar",
            len = 10,
            time = 123456789000000000,
            Pid = 3432,
            ["nested.a"] = "string",
            ["nested.b"] = 1,
            ["captain.jean-luc"] = '{"picard":{"v":"uss enterprise"}}'
        }
    }
}

local cnt = 0
function process_message()
    cnt = cnt + 1
    local received = decode_message(read_message("raw"))
    test.fields_array_to_hash(received)
    test.verify_msg(messages[cnt], received, cnt)
    return 0
end

function timer_event(ns)
    assert(cnt == #messages, string.format("%d of %d tests ran", cnt, #messages))
end
