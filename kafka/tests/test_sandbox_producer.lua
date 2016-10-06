-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "kafka"
require "string"

local producer = kafka.producer("localhost:9092",
                                         {
                                             ["topic.metadata.refresh.interval.ms"] = -1,
                                             ["batch.num.messages"] = 1,
                                             ["queue.buffering.max.ms"] = 1,
                                         })
local cnt = 0
local topic = "test"
local sid
local raw = read_message("raw", nil, nil, true)
function process_message(sequence_id)
    sid = sequence_id
    if cnt == 0 then
        local topic_tmp = "tmp"
        producer:create_topic(topic)
        assert(producer:has_topic(topic))
        assert(0 == producer:send(topic, -1, sequence_id, raw))

        producer:create_topic(topic_tmp)
        producer:create_topic(topic_tmp, nil)
        assert(producer:has_topic(topic_tmp))
        producer:destroy_topic(topic_tmp)
        assert(not producer:has_topic(topic_tmp))
        ok, err = pcall(producer.create_topic, producer, "topic", true)
        assert(err == "bad argument #3 to '?' (table expected, got boolean)", err)
        ok, err = pcall(producer.send, producer, "foobar", -1, sequence_id, raw)
        assert(err == "invalid topic", err)
    elseif cnt == 1 then
        assert(0 == producer:send(topic, -1, sequence_id, encode_message({Payload = "two"})))
    elseif cnt == 2 then
        assert(0 == producer:send(topic, -1, sequence_id, encode_message({Payload = "three"})))
    end
    cnt = cnt + 1
    return 0
end

function timer_event(ns)
    if sid then
        ok, err = pcall(producer.send, producer, topic, -1, sid, raw)
        assert(ok, "nil zero copy result should not error")
        sid = nil
    end
    producer:poll()
end
