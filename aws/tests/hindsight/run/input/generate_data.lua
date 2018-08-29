-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "aws.kinesis"
require "string"

local clientConfig = {region = "us-west-2"}
local streamName = "hindsight-test"

local tests = {
    {"message one", "\001"},
    {"message two", "\002"},
    {"message three", "\003"},
}

local tests_cnt = #tests

function process_message(cp)
    local reader = aws.kinesis.simple_consumer(streamName, "LATEST", nil, clientConfig)
    local writer = aws.kinesis.simple_producer(clientConfig)
    for i,v in ipairs(tests) do
        local rv, err = writer:send(streamName, v[1], v[2])
        if rv ~= 0 and err then print(err) end
    end

    local cnt = 0
    local rcnt = 0
    while cnt < 10 do
        local records, cp = reader:receive()
        for i, data in ipairs(records) do
            rcnt = rcnt + 1
            assert(tests[rcnt][1] == data, string.format("test %d expected: %s received %s", rcnt, tests[rcnt][1], data))
        end
        if rcnt == tests_cnt then return 0 end
        cnt = cnt + 1
    end
    assert(rcnt == tests_cnt, string.format("expected %d records, got %d", test_cnt, rcnt))
    return 0
end
