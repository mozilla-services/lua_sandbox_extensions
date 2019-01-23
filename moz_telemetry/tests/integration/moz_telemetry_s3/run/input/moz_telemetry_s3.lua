-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_telemetry_s3 and verifies the output
--]]

require "io"
require "string"

local inputs = {
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = string.rep("x", 256)}}, -- ignore filename that would be too large
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = "main"}},
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = "main", ["environment.experiments"] = '{"foo":{"branch":"123"}}'}},
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = "main", ["environment.experiments"] = '{"foo":{"branch":"123"}, "bar":{"branch":"456"}}'}},
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = "main", ["environment.experiments"] = '{"foo":{"branch":"123", "type":"normandy-preference-"}, "bar":{"branch":"456", "type":"another-type"}, "pref-flip-screenshots-release-1369150":{"branch":"789"}}'}},
    {Timestamp = 0, Type = "moz_telemetry_s3", Fields = { docType = "main", ["environment.experiments"] = '{"foo":{"branch":"123", "type":"normandy-exp"}, "bar":{"branch":"456", "type":"normandy-exp-highpop"}, "clicktoplay-rollout":{"branch":"789"}}'}}
}


local function check_message_count(fn, expected_cnt)
    local fh = assert(io.open(fn))
    local hsr = create_stream_reader("count")
    local cnt = 0
    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh)
            if found then cnt = cnt + 1 end
        until not found
    until read == 0
    fh:close()
    assert(cnt == expected_cnt, string.format("%s expected: %d received: %d", fn, expected_cnt, cnt))
end


function process_message()
    for i, v in ipairs(inputs) do
        inject_message(v)
    end

    for i = 1, 10 do
        local oh = assert(io.popen("sleep 1; ls output/moz_telemetry_s3"))
        local od = oh:read("*a")
        oh:close()

        local eh = assert(io.popen("ls output/moz_experiments_s3"))
        local ed = eh:read("*a")
        eh:close()

        if od:match("main\n") and ed:match("main%+foo%+123") and ed:match("main%+bar%+456")
            and not ed:match("main%+clicktoplay-rollout%+789")
            and not ed:match("main%+pref-flip-screenshots-release-1369150%+789") then
            check_message_count("output/moz_telemetry_s3/main", 5)
            check_message_count("output/moz_experiments_s3/main+foo+123", 4)
            check_message_count("output/moz_experiments_s3/main+bar+456", 1)
            return 0
        end
    end
    error("missing output")
end
