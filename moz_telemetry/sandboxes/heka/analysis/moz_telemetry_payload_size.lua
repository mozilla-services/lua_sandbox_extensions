-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Payload Size

Extract submission sizes and counts for pipeline messages, emitting small
derived messages for reporting.

## Sample Configuration
```lua
filename = "moz_telemetry_payload_size.lua"
message_matcher = "Type == 'telemetry' && Logger == 'telemetry'"
```
--]]

local msg = {
    Timestamp  = nil,
    Type       = "payload_size",
    Payload    = nil,
    Fields     = {
        build = "",
        channel = "",
        docType = "",
        size = 0,
        submissionDate = "",
    }
}

function process_message()
    msg.Timestamp = read_message("Timestamp")
    msg.Fields.build = read_message("Fields[appBuildId]")
    msg.Fields.channel = read_message("Fields[appUpdateChannel]")
    msg.Fields.docType = read_message("Fields[docType]")
    msg.Fields.size = read_message("size")

    -- This could be computed from msg.Timestamp, but we need the field for
    -- partitioning the data in the S3 Output.
    msg.Fields.submissionDate = read_message("Fields[submissionDate]")

    inject_message(msg)
    return 0
end

function timer_event(ns)

end
