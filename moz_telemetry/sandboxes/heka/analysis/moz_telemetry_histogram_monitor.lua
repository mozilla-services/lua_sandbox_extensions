-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Histogram Analysis Using Pearson's Correlation Coefficient

Analyzes each histogram for any change in behavior.

## Sample Configuration

```lua
filename = "moz_telemetry_histogram_monitor.lua"
ticker_interval = 600
preserve_data = true
message_matcher = "Uuid < '\003' && Fields[normalizedChannel] == 'release' && Fields[docType] == 'main' && Fields[appVendor] == 'Mozilla' && Fields[payload.histograms] != NIL" -- slightly greater than a 1% sample

histogram_samples  = 25 -- number of histograms to compare 24 historical + current interval
histogram_interval = 3600  -- collection period for each histogram

alert = {
  disabled = false,
  prefix = true,
  throttle = histogram_interval,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    -- pcc = 0.3, -- default minimum correlation coefficient (less than or equal alerts)
    -- submissions = 1000, -- default minimum number of submissions before alerting in at least the current and one previous interval
    -- ignore = {}  -- hash of histograms to ignore e.g. 'histogram_name = true'
    active = histogram_interval  * 5, -- number of seconds after histogram creation before alerting
  }
}
```
--]]
_PRESERVATION_VERSION = (read_config("preservation_version") or 0) + 1
ebuckets   = {} -- cache for the exponential histogram bucket hash
histograms = nil
interval = 0

require "cjson"
require "string"
local floor = require "math".floor
local mth   = require "moz_telemetry.histogram"

local ticker_interval       = read_config("ticker_interval")
local histogram_samples     = read_config("histogram_samples") or 25
local histogram_interval    = read_config("histogram_interval") or 3600
histogram_interval          = histogram_interval * 1e9
histograms                  = mth.create(histogram_samples, ebuckets)


function process_message()
    local ns = read_message("Timestamp")
    local cint = floor(ns / histogram_interval)
    local row = cint % histogram_samples + 1
    if cint > interval then
        mth.clear_row(histograms, row) -- only cleanup the new target interval
        interval = cint
    end

    local ok, json = pcall(cjson.decode, read_message("Fields[payload.histograms]"))
    if not ok then return -1, json end
    mth.process(ns, json, histograms, row)
    return 0
end


local schema_name   = "histograms"
local schema_ext    = "json"
function timer_event(ns, shutdown)
    if shutdown then return end

    local graphs = {}
    local current_row = interval % histogram_samples + 1
    add_to_payload(string.format('{"current_row":%d,"histograms":{', current_row))
    mth.output(histograms, current_row, graphs)
    add_to_payload("}}")
    inject_payload(schema_ext, schema_name)
    if ns % histogram_interval >= histogram_interval - ticker_interval then
        mth.alert(graphs) -- only alert when the current interval is nearly complete
    end
    mth.output_viewer_html(schema_name, schema_ext)
end
