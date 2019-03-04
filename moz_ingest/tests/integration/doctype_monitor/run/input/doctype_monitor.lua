-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_ingest_doctype_monitor
--]]

require "string"

local tm = {
    Logger = "telemetry",
    Type = "telemetry",
    Fields = {
        docType = "main",
        normalizedChannel  = nil,
        appBuildId = "19701001000000",
        }
    }

function process_message()
    local ns = 365 * 86400e9
    tm.Fields.normalizedChannel = "nightly"
    tm.Type = "telemetry.error"
    tm.Fields.DecodeError = "should not be counted, old build"
    for i=0, 62 do
        ns = ns + 60e9
        tm.Timestamp = ns
        for j=1, 50 do
            inject_message(tm)
        end
    end
    tm.Type = "telemetry"
    tm.Fields.DecodeError = nil
    tm.Fields.appBuildId = "19701201000000"

    for i=0, 62 do  -- clear creation threshold
        ns = ns + 60e9
        tm.Timestamp = ns
        tm.Fields.normalizedChannel = "release"
        inject_message(tm)
    end

    for i=1, 60 do
        ns = ns + 60e9
        tm.Timestamp =  ns
        tm.Fields.normalizedChannel = "release"
        if i < 15 or i > 20 then inject_message(tm) end

        tm.Fields.normalizedChannel = "beta"
        for j=1, 50 do
            inject_message(tm)
        end

        tm.Fields.normalizedChannel = "nightly"
        for j=1, 50 do
           inject_message(tm)
        end
    end

    for i=1, 31 do
        tm.Fields.normalizedChannel = "beta"
        tm.Type = "telemetry.duplicate"
        inject_message(tm)

        tm.Fields.normalizedChannel = "nightly"
        tm.Type = "telemetry.error"
        tm.Fields.DecodeError = "foobar"
        inject_message(tm)
        tm.Type = "telemetry"
        tm.Fields.DecodeError = nil
    end

    tm.Type = "telemetry"
    tm.Fields.normalizedChannel = "Other"
    tm.Fields.submission = "submission data to capture"
    inject_message(tm)
    tm.Fields.submission = nil

    ns = ns + 60e9
    tm.Timestamp =  ns
    tm.Type = "telemetry.error"
    tm.Fields.DecodeError = "parse"
    tm.Fields.DecodeErrorDetail = "parse error"
    inject_message(tm)
    tm.Type = "telemetry"
    tm.Fields.DecodeError = nil
    tm.Fields.DecodeErrorDetail = nil

    for i=1, 150 do -- clear error alert
        tm.Fields.normalizedChannel = "nightly"
        inject_message(tm)
    end

    for i=1, 250 do -- clear duplicate alert
        tm.Fields.normalizedChannel = "beta"
        inject_message(tm)
    end

    ns = ns + 60e9
    tm.Timestamp =  ns
    tm.Fields.normalizedChannel = "nightly" -- induce another alert with the same top error (should be suppressed)
    tm.Type = "telemetry.error"
    tm.Fields.DecodeError = "foobar"
    inject_message(tm)

    tm.Fields.DecodeError = "parse" -- induce an alert with new top error
    for i=1, 32 do
        inject_message(tm)
    end
    ns = ns + 60e9
    tm.Timestamp =  ns
    inject_message(tm)

    return 0
end
