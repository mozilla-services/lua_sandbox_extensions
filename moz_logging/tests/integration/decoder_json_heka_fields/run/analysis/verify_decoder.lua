-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {Logger = "input.test_decoder", Type = "error", Hostname = "integration_test",
        Payload = "inject_message() failed: unsupported array type: table",
        Fields = {
            data = '{"Logger":"input1", "Items":[{}]}'
        }
    },
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test",
        Fields = {
            Logger = "input2",
            Type = "type2"
        }
    },
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test",
        Fields = {
            Timestamp = 123456789,
            bstring = {value = "binary", value_type = 1},
            foo = "bar"
        }
    },
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test",
        Fields = {
            array = {value={1,2,3}, value_type=2, representation="count"}
        }
    },
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
