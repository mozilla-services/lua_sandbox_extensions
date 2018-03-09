-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {
        Logger = "input.multiline",
        Hostname = "integration_test",
        Payload = "This is\na test\nitem\nlong\nlong\nline\n",
    },
    {
        Logger = "input.multiline",
        Hostname = "integration_test",
        Payload = "This is log line 2\n",
    },
    {
        Logger = "input.multiline",
        Hostname = "integration_test",
        Payload = "This is log\nline\nthree\n<eol>\n",
    }
}

local cnt = 0
function process_message()
    cnt = cnt + 1
    local received = decode_message(read_message("raw"))
    test.verify_msg(messages[cnt], received, cnt)
    return 0
end

function timer_event(ns)
    assert(cnt == #messages, string.format("%d of %d tests ran", cnt, #messages))
end
