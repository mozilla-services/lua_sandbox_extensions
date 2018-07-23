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
message_matcher = "Uuid < '\003' && Fields[normalizedChannel] == 'release' && Fields[payload.histograms] != NIL" -- slightly greater than a 1% sample

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
    -- submissions = 1000, -- default minimum number of submissions before alerting
    -- ignore = {}  -- hash of histograms to ignore e.g. 'histogram_name = true'
    active = histogram_interval  * 5, -- number of seconds after histogram creation before alerting
  }
}
```
--]]
_PRESERVATION_VERSION   = read_config("preservation_version") or 1
ebuckets   = {}
histograms = nil
interval = 0

require "cjson"
require "string"
local floor         = require "math".floor
local alert         = require "heka.alert"
local escape_json   = require "lpeg.escape_sequences".escape_json
local mth           = require "moz_telemetry.histogram"

local ticker_interval       = read_config("ticker_interval")
local histogram_samples     = read_config("histogram_samples") or 25
local histogram_interval    = read_config("histogram_interval") or 3600
histogram_interval          = histogram_interval * 1e9

histograms = mth.create(histogram_samples, ebuckets)


function process_message()
    local ns = read_message("Timestamp")
    local cinterval = floor(ns / histogram_interval)
    local row = cinterval % histogram_samples + 1
    if cinterval > interval then
        mth.clear_row(histograms, row) -- only cleanup the new target interval
        interval = cinterval
    end

    local ok, json = pcall(cjson.decode, read_message("Fields[payload.histograms]"))
    if not ok then return -1, json end
    mth.process(ns, json, histograms, row)
    return 0
end


local viewer
local viewer1
local schema_name   = "histograms"
local schema_ext    = "json"
function timer_event(ns, shutdown)
    if shutdown then return end

    local current_row = interval % histogram_samples + 1
    add_to_payload(string.format('{"current_row":%d,"histograms":{', current_row))
    local graphs = {}
    mth.output(histograms, current_row, graphs)
    add_to_payload("}}")
    inject_payload(schema_ext, schema_name)
    if ns % histogram_interval >= histogram_interval - ticker_interval then
        mth.alert(graphs)
    end

    if viewer then
        inject_payload("html", "viewer", viewer, alert.get_dashboard_uri(schema_name, schema_ext), viewer1)
        viewer = nil
        viewer1 = nil
    end
end


viewer = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.16/css/jquery.dataTables.css">
<script type="text/javascript" charset="utf8" src="https://code.jquery.com/jquery-3.3.1.js">
</script>
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.10.16/js/jquery.dataTables.min.js">
</script>
<script type="text/javascript">
function fetch(url, callback) {
  var req = new XMLHttpRequest();
  var caller = this;
  req.onreadystatechange = function() {
    if (req.readyState == 4) {
      if (req.status == 200 ||
        req.status == 0) {
        callback(JSON.parse(req.responseText));
      } else {
        var p = document.createElement('p');
        p.innerHTML = "data retrieval failed: " + url;
        document.body.appendChild(p);
      }
    }
  };
  req.open("GET", url, true);
  req.send(null);
}

function load(schema) {
  data = [ ];
  for (key in schema.histograms) {
    var v = schema.histograms[key];
    v.name = key;
    data.push(v);
  }

  $('#histograms').DataTable( {
    data: data,
    order: [ [0, "asc"] ],
    columns: [
    { title: "Name", data: "name" },
    { title: "Alerted", data: "alerted" },
    { title: "Buckets", data: "bucket_count" },
    { title: "Type", data: "histogram_type" },
    { title: "Submissions", data: "submissions" },
    { title: "PCC", data: "pcc", defaultContent: '' },
    { title: "ClosestRow", data: "closest_row", defaultContent: '' }
      ]
  });
}
</script>
</head>
<body onload="fetch(']]

viewer1 =
[[', load);">
<div>
    <h1>Histograms</h1>
    <table id="histograms" width="100%">
    </table>
</div>
</body>
</html>
]]
