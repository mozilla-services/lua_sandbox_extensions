-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {Logger = "input.test_decoder", Type = "error", Hostname = "integration_test",
        Payload = "inject_message() failed: field name must be a string",
        Fields = {
            data = '{"Logger":"input1", "Fields":[{}]}'
        }
    },
    {Logger = "input.test_decoder|input1", Type = "default", Hostname = "integration_test"},
    {Logger = "input.test_decoder|input2", Type = "default|type2", Hostname = "integration_test"},
    {Logger = "input.test_decoder|input2", Type = "default|type2", Hostname = "integration_test",
        Fields = {
            user_agent_browser = "Firefox",
            agent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:27.0) Gecko/20100101 Firefox/27.0",
            user_agent_os = "Linux",
            user_agent_version = 27
        }
    },
    {Logger = "input.test_decoder|input2", Type = "default|type2", Hostname = "integration_test",
        Fields = {
            foo = "bar",
        }
    },
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test",
        Fields = {
            ["deep.level1.level2.level3"] = '{"level4":"value"}',
            Timestamp = 123456789,
            foo = "bar",
            ["nested.level1"] = "l1"
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
