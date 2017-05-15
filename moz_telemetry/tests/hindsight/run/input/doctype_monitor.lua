-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_telemetry_doctype_monitor
--]]

require "string"

local tm = {
    Type = "telemetry", 
    Fields = {
        docType = "main",
        creationTimestamp = nil,
        normalizedChannel = nil,
        duplicateDelta    = nil,
        extra             = nil,
        }
    }

function process_message()
    local ns =  8 * 86400e9
    for i=0, 1439 do  -- volume (beta) and shape (Other) need history
        tm.Timestamp = i * 60e9 + ns
        tm.Fields.creationTimestamp = tm.Timestamp
        tm.Fields.normalizedChannel = "beta"
        for j=1, 20 do
            inject_message(tm)
        end
        tm.Fields.normalizedChannel = "Other"
        for j=1, 20 do
            inject_message(tm)
        end
    end

   for i=0, 1440 do
       tm.Timestamp = i * 60e9 + ns + 86400e9 * 7
       tm.Fields.creationTimestamp = tm.Timestamp
       tm.Fields.normalizedChannel = "beta"
       for j=1, 25 do
           inject_message(tm)
       end

       tm.Fields.normalizedChannel = "esr"
       for j=1, 20 do
           inject_message(tm)
       end
       if i >= 120 then
           tm.Type = "telemetry.duplicate"
       end
       inject_message(tm)
       tm.Type = "telemetry"

       tm.Fields.normalizedChannel = "aurora"
       for j=1, 19 do
           inject_message(tm)
       end
       if i >= 1380 then
           tm.Type = "telemetry.error"
           tm.Fields.DecodeError = "foobar"
           inject_message(tm)
           tm.Type = "telemetry"
           tm.Fields.DecodeError = nil
       end

       tm.Fields.normalizedChannel = "nightly"
       if i >= 900 then
           tm.Fields.extra = string.rep("x", 100)
       end
       for j=1, 25 do
           inject_message(tm)
       end
       tm.Fields.extra = nil

       tm.Fields.normalizedChannel = "release"
       if i >= 1380 then
           tm.Fields.creationTimestamp = tm.Timestamp - (i - 1380) * 3600e9
       end
       for j=1, 20 do
           inject_message(tm)
       end
   end
    return 0
end
