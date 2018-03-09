-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for heka table_to_message decoder
--]]

require "string"
local test = require "test_verify_message"

local messages = {
    {
        Timestamp = 123456789000000000,
        Logger = "input.function",
        Type = "default_header",
        Hostname = "integration_test",
        Pid = 3432,
        Fields = {
            foo = "bar",
            length = {value = 10, value_type = 2, representation = "inches"},
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
