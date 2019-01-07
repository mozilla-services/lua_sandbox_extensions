-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "os"
require "string"
local test = require "test_verify_message"

local messages = {
    {
        Timestamp = os.time({year = os.date("%Y"), month = 2, day = 13, hour = 14, min = 25, sec = 19}) * 1e9,
        Logger = "input.printf",
        Hostname = "ubuntu",
        Payload = "Accepted publickey for foobar from 216.160.83.56 port 4242 ssh2",
        Pid = 7192,
        Fields = {
            ssh_remote_port = 4242,
            method = "publickey",
            user = "foobar",
            ssh_remote_ipaddr = {value = "216.160.83.56", representation = "ipv4"},
            programname = "sshd",
            extra = "",
            authmsg = "Accepted"
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
