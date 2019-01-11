-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_telemetry_mobile_monitor
--]]

require "string"

local tm = {
    Type = "telemetry",
    Fields = {
        appName             = "Focus",
        normalizedChannel   = "release",
        normalizedOs        = "iOS",
        docType             = "core",
        }
    }

function process_message()
    local ns =  8 * 86400e9
    for i=1, 61 do
        tm.Timestamp = ns
        inject_message(tm)
        ns = ns + 60e9
    end

    tm.Fields.appName = "Klar" -- trigger the timeout in "Focus"
    for i=1, 6 do
        tm.Timestamp = ns
        inject_message(tm)
        ns = ns + 60e9
    end

    tm.Fields.appName = "Focus"
    for i=1, 1000 do
        tm.Timestamp = ns
        inject_message(tm)
    end

    tm.Type = "telemetry.error"
    tm.Fields.DecodeError = "error type 1"
    for i=1, 5 do
        tm.Timestamp = ns
        inject_message(tm)
    end

    tm.Fields.DecodeError = "error type 2"
    for i=1, 4 do
        tm.Timestamp = ns
        inject_message(tm)
    end

    tm.Fields.DecodeError = "error type 3"
    for i=1, 3 do
        tm.Timestamp = ns
        inject_message(tm)
    end

    ns = ns + 60e9
    tm.Timestamp = ns
    tm.Type = "telemetry"
    tm.Fields.appName = "Klar"
    tm.Fields.DecodeError = nil
    inject_message(tm) -- trigger the timer event

   return 0
end
