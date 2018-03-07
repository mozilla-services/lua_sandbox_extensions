-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_telemetry_new_doctype_monitor
--]]

require "string"

local message = { Type = "telemetry-new-doc-type", Fields = { docType = "main" }}

-- base timestamp for the test
local base_timestamp = 8 * 86400e9

-- increase the timestamp value in minutes
function timestep(base, minutes)
    return base + (minutes * 60e9)
end

-- send message with different doctypes 
function send_message(timestamp, doctype)
    message.Timestamp = timestamp
    message.Fields.docType = doctype
    inject_message(message)
end

-- Inject the messaging queue with mocked data. The alerting threshold for tests will be 10 documents. 
function process_message()
    local ts = base_timestamp
    for step=1, 1440 do
        --[[ Test behavior from initial conditions, with a single alert

            - existing doctype (blacklist)
            - new doctypes above threshold (alert)
            - doctype below threshold

            expect "test_message_1"
        --]]

        ts = timestep(ts, 1)

        -- send a message every minute
        send_message(ts, "main")

        if step == 1 then
            for i=1, 10 do send_message(ts, "main") end
            for i=1, 10 do send_message(ts, "test_message_1") end
            for i=1, 5  do send_message(ts, "test_message_2") end
        end

        -- Test throttling behavior by adding a new doctype, this is offset by at least 90 minutes from the prevous case
        if step == 105 then
            for i=1, 10 do send_message(ts, "test_message_3") end
        end

        --[[ TODO: Alerts sent via heka.alerts are not sent during CI because the ticker interval is
             driven by the timestamps in the injected messages. The alerting module uses the wall clock
             instead. The tests below will not alert. See PR in bug 1174882 for more details.
        --]]

        --[[ Test state across timer events and an alert with more than one doctype

            - doctype that has been added to the blacklist
            - tracked doctype above threshold
            - new doctype above threshold
            - doctype below threshold

            expect "test_message_2" and "test_message_3"
        --]]
        if step == 190 then
            for i=1, 10 do send_message(ts, "test_message_1") end
            for i=1, 5  do send_message(ts, "test_message_2") end
            for i=1, 5  do send_message(ts, "test_message_4") end
        end

        --[[ Test the reset behavior after a day

            - doctype tracked in the previous day with its count reset
            - doctype that was added to the blacklist in the previous day
            - new doctype above threshold

            expect "test_message_5"
        --]]
        if step == 1440 then
            for i=1, 6  do send_message(ts, "test_message_4") end
            for i=1, 10  do send_message(ts, "test_message_1") end
            for i=1, 10  do send_message(ts, "test_message_5") end
        end
    end
    return 0
end
