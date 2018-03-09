-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = read_config("messages")
local len = #messages
local cnt = 0
function process_message()
    cnt = cnt + 1
    local received = decode_message(read_message("raw"))
    local ok, err = pcall(test.verify_msg, messages[cnt], received, cnt)
    if not ok or cnt == len then
        inject_message({Type = "shutdown", Payload = received.Logger})
        if not ok then error(err) end
    end
    return 0
end

function timer_event(ns)
    assert(cnt == len, string.format("%d of %d tests ran", cnt, len))
end
