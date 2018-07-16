-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_telemetry_new_experiment_monitor
--]]

require "string"

local tm = {
    Type = "telemetry",
    Fields = {
        docType = "main",
        ["environment.experiments"] = nil,
        submission = nil,
    }
}

function process_message()
    -- Send an already-known experiment. Should not generate any alert.
    tm.Timestamp = 1 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"e10sCohort": {"branch": "example"}}'
    inject_message(tm)

    -- Send a new experiment. Should generate an alert.
    tm.Timestamp = 2 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"foo": {"branch": "example"}}'
    inject_message(tm)

    -- Send it again. No alert expected.
    tm.Timestamp = 3 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"foo": {"branch": "example"}}'
    inject_message(tm)

    -- Send our earlier experiment. Should not generate any alert.
    tm.Timestamp = 4 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"e10sCohort": {"branch": "example"}}'
    inject_message(tm)

    -- Send a test message with a new experiment id. Should not generate any alert.
    tm.Timestamp = 5 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"test_experiment": {"branch": "example"}}'
    tm.Fields["submission"] = '{"payload":{"test": true}}'
    inject_message(tm)

    -- Send another new experiment. Should generate another alert.
    tm.Timestamp = 6 * 60e9 + 8 * 86400e9
    tm.Fields["environment.experiments"] = '{"bar": {"branch": "example"}}'
    tm.Fields["submission"] = nil
    inject_message(tm)

    return 0
end
