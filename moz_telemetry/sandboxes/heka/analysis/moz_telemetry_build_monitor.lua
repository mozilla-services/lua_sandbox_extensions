-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Build Monitor

Analyzes all the histograms looking for any significant differences between the
current and previous builds partitioned by normalized OS.

## Sample Configuration

```lua
filename = "moz_telemetry_build_monitor.lua"
ticker_interval = 600
preserve_data = true
message_matcher = "Uuid < '\003' && Fields[os] =~ 'Windows' && Fields[normalizedChannel] == 'release' && Fields[docType] == 'main' && Fields[appVendor] == 'Mozilla' && Fields[payload.histograms] != NIL" -- slightly greater than a 1% sample

number_of_builds = 5 -- default, number of builds to monitor >= 2

alert = {
  disabled = false,
  prefix = true,
  throttle = ticker_interval,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    -- pcc = 0.3,    -- default minimum correlation coefficient (less than or equal alerts)
    -- submissions = 1000, -- default minimum number of submissions before alerting in at least the current and one previous build
    -- ignore = {} -- hash of histograms to ignore e.g. 'histogram_name = true'
    active = 3600, -- number of seconds after histogram/build creation before alerting
  }
}
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 1
ebuckets    = {} -- cache for the exponential histogram bucket hash
data        = nil

require "cjson"
require "os"
require "string"
local l     = require "lpeg";l.locale(l)
local mth   = require "moz_telemetry.histogram"

local alert_active  = read_config("alert").thresholds.active or 3600
alert_active = alert_active * 1e9
local number_of_builds = read_config("number_of_builds") or 5
assert(number_of_builds >= 2, "number_of_build must be >= 2")
data  = {
    current_row     = 0,
    builds_count    = 0,
    builds          = {},
    histograms      = mth.create(number_of_builds, ebuckets)
}

local grammar = l.Ct(
    l.Cg(l.digit^-4, "year")
    * l.Cg(l.digit^-2, "month")
    * l.Cg(l.digit^-2, "day")
    * l.Cg(l.digit^-2, "hour")
    * l.Cg(l.digit^-2, "min")
    * l.Cg(l.digit^-2, "sec")
    ) / os.time * l.P(-1)


local function find_build(ns, bid, bts)
    local b = data.builds[bid]
    if not b then
        if data.builds_count == number_of_builds then
            local oldest = bts
            local key = nil
            for k,v in pairs(data.builds) do
                if v.ts < oldest then
                    oldest = v.ts
                    key = k
                end
            end
            if key then
                b = data.builds[key]
                data.builds[key] = nil
                b.ts = bts
                b.created = ns
                b.submissions = 0
                mth.clear_row(data.histograms, b.row)
                data.builds[bid] = b
            else
                return -- old build ignore
            end
        else
            data.builds_count = data.builds_count + 1
            b = {created = ns, row = data.builds_count, ts = bts, submissions = 0}
            data.builds[bid] = b
        end
        local newest = -1
        for k,v in pairs(data.builds) do
            if v.ts > newest then
                newest = v.ts
                data.current_row = v.row
            end
        end
    end
    b.submissions = b.submissions + 1
    return b.row
end


function process_message()
    local bts = nil
    local bid = read_message("Fields[appBuildId]")
    if bid then bts = grammar:match(bid) end
    if not bid or not bts then return 0 end

    local ns = read_message("Timestamp")
    local row = find_build(ns, bid, bts)
    if row then
        local ok, json = pcall(cjson.decode, read_message("Fields[payload.histograms]"))
        if not ok then return -1, json end
        mth.process(ns, json, data.histograms, row)
    end
    return 0
end


local schema_name   = "builds"
local schema_ext    = "json"
function timer_event(ns, shutdown)
    if shutdown then return end

    local created = ns
    add_to_payload(string.format('{"builds_count":%d,"current_row":%d,"builds":{',
                                 data.builds_count, data.current_row))
    local sep = ""
    for k, v in pairs(data.builds) do
        add_to_payload(string.format('%s"%s":{"created":%d,"submissions":%d,"row":%d,"ts":%d}',
                                     sep, k, v.created, v.submissions, v.row, v.ts))
        sep = ","
        if v.row == data.current_row then created = v.created end
    end

    local graphs = {}
    add_to_payload('},"histograms":{')
    mth.output(data.histograms, data.current_row, graphs)
    add_to_payload("}}")
    inject_payload(schema_ext, schema_name)
    if ns - created > alert_active then
        mth.alert(graphs)
    end
    mth.output_viewer_html(schema_name, schema_ext)
end
