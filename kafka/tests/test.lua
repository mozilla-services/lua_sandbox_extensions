-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "kafka"
require "string"
assert(kafka.version() == "1.0.5", kafka.version())

local producer = kafka.producer("localhost:9092",
                                    {
                                        ["topic.metadata.refresh.interval.ms"] = -1,
                                        ["batch.num.messages"] = 1,
                                        ["queue.buffering.max.ms"] = 1,
                                    })

local topic = "test"
local topic_tmp = "tmp"
producer:create_topic(topic)
assert(producer:has_topic(topic))
assert(0 == producer:send(topic, -1, 1, "one"))

producer:create_topic(topic_tmp)
producer:create_topic(topic_tmp, nil)
assert(producer:has_topic(topic_tmp))
producer:destroy_topic(topic_tmp)
assert(not producer:has_topic(topic_tmp))
ok, err = pcall(producer.create_topic, producer, "topic", true)
assert(err == "bad argument #3 to '?' (table expected, got boolean)", err)
ok, err = pcall(producer.send, producer, "foobar", -1, 1, "msg x")
assert(err == "invalid topic", err)
assert(0 == producer:send(topic, -1, 2, "two"))
assert(0 == producer:send(topic, -1, 3, "three"))
local sid, failures
local cnt = 0
repeat
    sid, failures = producer:poll(1000)
    cnt = cnt + 1
    if cnt == 10 then
        error("timedout out waiting for delivery confirmation")
    end
until sid == 3


local consumer = kafka.consumer("localhost:9092", {"test"}, {["group.id"] = "integration_testing"}, {["auto.offset.reset"] = "smallest"})
local consumer1 = kafka.consumer("localhost:9092", {"test:1"}, {["group.id"] = "other"})
local pb, topic, partition, key = consumer1:receive()
assert(not pb)

local payloads = {"one", "two", "three"}

local cnt = 0
for i=1, 10 do
    msg, topic, partition, key = consumer:receive()
    if msg then
        cnt = cnt + 1
        if msg ~= payloads[cnt] then
            return -1, string.format("expected: %s received: %s", payloads[cnt], msg)
        end
        if cnt == 3 then return 0 end
    end
end
error(string.format("received %d/3 messages", cnt))
