-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "kafka"
require "string"

local consumer = kafka.consumer("localhost:9092", {"test"}, {["group.id"] = "integration_testing"}, {["auto.offset.reset"] = "smallest"})
local consumer1 = kafka.consumer("localhost:9092", {"test:1"}, {["group.id"] = "other"})
local pb, topic, partition, key = consumer1:receive()
assert(not pb)

local payloads = {"one", "two", "three"}

function process_message()
    local cnt = 0
    for i=1, 10 do
        pb, topic, partition, key = consumer:receive()
        if pb then
            cnt = cnt + 1
            local msg = decode_message(pb)
            if msg.Payload ~= payloads[cnt] then
                return -1, string.format("expected: %s received: %s", payloads[cnt], msg.Payload)
            end
            if cnt == 3 then return 0 end
        end
    end
    return -1, string.format("received %d/3 messages", cnt)
end
