-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Test Pilot Event-Based Installation Counts

The output of this notebook is used to fill in the installation counts from
testpilot.firefox.com. The way we calculate these counts is:

    * Count all the enable and disable events since the switchover to
      event-based pings
    * Add all the enable and the disable to our baseline numbers (the
      approximate number of installations we had before moving to event-based
      pings)
    * Output these numbers to a publicly-accessible json file (available at
      https://analysis-output.telemetry.mozilla.org/testpilot/data/installation-counts/latest.json)
      -- note we output the results to latest.json as well as <timestamp>.json

Please note these numbers are calculated for the sole purpose of giving an
approximation to end-users and should absolutely not be used for decision-making.

See the original notebook: 
http://nbviewer.jupyter.org/urls/s3-us-west-2.amazonaws.com/telemetry-public-analysis-2/txp_install_counts/data/TxP%20Event-based%20Install%20Counts.ipynb

## Sample Configuration
```lua
filename        = "moz_testpilot_installation.lua"
message_matcher = "Type == 'telemetry' && Fields[docType] == 'testpilot' && Fields[appName] == 'Firefox'"
preserve_data   = true
ticker_interval = 60
```

## Sample Output
```json
{
    "@testpilot-addon": 216983, 
    "@foo-bar": 0, 
    "jid1-NeEaf3sAHdKHPA@jetpack": 170445, 
    "blok@mozilla.org": 51219, 
    "@min-vid": 93738, 
    "@activity-streams": 107032, 
    "@x16": 8, 
    "tabcentertest1@mozilla.com": 72869, 
    "universal-search@mozilla.com": 131783,
    "wayback_machine@mozilla.org": 49099
}

```
--]]

_PRESERVATION_VERSION = 1

require "cjson"
-- require "hyperloglog"
-- active_clients = hyperloglog.new()

event_counts  = {}

function process_message()
    --active_clients:add(tostring(read_message("Fields[clientId]")))
    local ok, doc = pcall(cjson.decode, read_message("Fields[submission]"))
    if not ok then return -1, doc end
    if type(doc.payload) ~= "table" then return -1, "payload is not a table" end
    if doc.payload.version == 1 then return 0 end

    local events = doc.payload.events
    if type(events) ~= "table" then return 0 end

    for i,v in ipairs(events) do
        local event = v.event
        local object = v.object or "__nil__"
        if event == "enabled" then
            local cnt = event_counts[object]
            if not cnt then
                event_counts[object] = 1
            else
                event_counts[object] = cnt + 1
            end
        elseif event == "disabled" then
            local cnt = event_counts[object]
            if not cnt then
                event_counts[object] = -1
            else
                event_counts[object] = cnt - 1
            end
        end
    end
    return 0
end


function timer_event(ns, shutdown)
    inject_payload("json", "counts", cjson.encode(event_counts))
    --inject_payload("txt", "active_clients", active_clients:count())
end
