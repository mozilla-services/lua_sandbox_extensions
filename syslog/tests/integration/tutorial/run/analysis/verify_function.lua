-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "os"
require "string"
local test = require "test_verify_message"

local messages = {
    {
        Timestamp = os.time({year = os.date("%Y"), month = 1, day = 23, hour = 8, min = 50, sec = 2}) * 1e9,
        Logger = "input.function",
        Hostname = "ubuntu",
        Payload = '127.0.0.1 - - [10/Feb/2014:08:46:41 -0800] "GET / HTTP/1.1" 304 0 "-" "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0"',
        Pid = 1234,
        Fields = {
            remote_user = "-",
            http_user_agent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0",
            body_bytes_sent = {value = 0, value_type = 3, representation = "B"},
            remote_addr = {value = "127.0.0.1", representation = "ipv4"},
            time = 1.392050801e+18,
            request = "GET / HTTP/1.1",
            programname = "nginx",
            http_referer = "-",
            status = 304
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
