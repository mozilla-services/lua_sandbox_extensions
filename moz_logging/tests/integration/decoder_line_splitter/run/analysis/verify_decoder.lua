-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test", Payload = "line one"},
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test", Payload = "line two"},
    {Logger = "input.test_decoder", Type = "default", Hostname = "integration_test", Payload = "line three"},
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
