-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# New Experiment Monitor

Send an alert email when a new Experiment ID is observed in a Telemetry `main` ping.

## Sample Configuration

```lua
filename = 'moz_telemetry_new_experiment_monitor.lua'
ticker_interval = 60
message_matcher = 'Type == "telemetry" && Fields[docType] == "main" && Fields[environment.experiments] != NIL'
preserve_data = true
alert = {
  modules = {
    email = {recipients = {'example@mozilla.com'}},
  },
  throttle = 1,
  disabled = false,
  prefix = false,
}
```
--]]

local alert = require "heka.alert"
local cjson = require "cjson"
local table = require "table"
local string = require "string"

alerted = {
    ["clicktoplay-rollout"] = true,
    ["e10sCohort"] = true,
    ["fxmonitor@shield.mozilla.org"] = true,
    ["pref-flip-activity-stream-60-release-pocket-spocs-optimization-1458310"] = true,
    ["pref-hotfix-tls-13-avast-rollback"] = true,
    ["rollout-rdl"] = true,
    ["searchCohort"] = true,
}

new_experiments = {}

function process_message()
    local ee_txt = read_message("Fields[environment.experiments]")
    if not ee_txt then
        return 0
    end

    local ee = cjson.decode(ee_txt)
    if  not ee then
        return 0
    end

    for experiment_id, branch_info in pairs(ee) do
        if not alerted[experiment_id] then
            alerted[experiment_id] = true
            table.insert(new_experiments, string.format("New experiment id observed: %s: %s", experiment_id, cjson.encode(branch_info)))
        end
    end
    return 0
end

function timer_event(ns, shutdown)
    if #new_experiments > 0 then
        local message = table.concat(new_experiments, "\n")
        new_experiments = {}
        alert.send("new_experiments", "New experiments observed", message)
    end
end
