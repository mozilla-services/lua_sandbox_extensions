-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {
        Timestamp = 1392050801000000000,
        Logger = "input.decoder_module",
        Hostname = "ubuntu",
        Pid = 1234,
        Fields = {
            body_bytes_sent = {value = 0, value_type = 3, representation = "B"},
            remote_addr = {value = "127.0.0.1", representation = "ipv4"},
            http_referer = "-",
            status = 304,
            request = "GET / HTTP/1.1",
            programname = "nginx",
            remote_user = "-",
            http_user_agent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0"
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
