-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Histogram Analysis Using Pearson's Correlation Coefficient

Analyzes each histogram for any change in behavior.

## Sample Configuration

```lua
filename = "moz_telemetry_histogram_monitor.lua"
ticker_interval = 3600
preserve_data = true
message_matcher = "Uuid < '\003' && Fields[normalizedChannel] == 'release' && Fields[payload.histograms] != NIL" -- slightly greater than a 1% sample

histogram_samples  = 26 -- number of histograms to compare 24 historical, 1 last hour, 1 current hour
histogram_interval = ticker_interval  -- collection period for each histgram

alert = {
  disabled = false,
  prefix = true,
  throttle = ticker_interval,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    pcc = 0, -- default minimum correlation coefficient (less than or equal alerts)
    samples = 1000, -- default minimum number of samples before alerting
    active = 5, -- default minimum number of samples with data
    ignore = {}  -- hash of histograms to ignore e.g. 'histogram_name = true'
  }
}
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0
histograms = {}
ebuckets   = {}

require "math"
require "string"
require "table"
require "cjson"
local alert       = require "heka.alert"
local sats        = require "streaming_algorithms.time_series"
local matrix      = require "streaming_algorithms.matrix"
local escape_json = require "lpeg.escape_sequences".escape_json
local escape_html = require "lpeg.escape_sequences".escape_html

local histogram_samples     = read_config("histogram_samples") or 26
local histogram_interval    = read_config("histogram_interval") or 3600
histogram_interval          = histogram_interval * 1e9
local alert_pcc             = alert.get_threshold("pcc") or 0
local alert_submissions     = alert.get_threshold("submissions") or 1000
local alert_active          = alert.get_threshold("active") or 5
local alert_ignore          = alert.get_threshold("ignore") or {}

local histogram_entry = [[
<div id="%s""</div>
<script type="text/javascript">
MG.data_graphic({
    title: '%s',
    data: [%s],
    binned: true,
    chart_type: 'histogram',
    width: 1024,
    target: '#%s',
    x_accessor: 'x',
    y_accessor: 'y'
});</script>
]]

local function get_last_complete_idx(h)
    local idx = math.floor(h.submissions:current_time() / histogram_interval) % histogram_samples - 1
    if idx == 0 then idx = histogram_samples end
    return idx;
end


local function debug_histogram(h, pcc, idx, closest, title, stats)
    local curr = h.m:get_row(idx)
    local cdata = {}
    for x,y in ipairs(curr) do
        cdata[x] = string.format("{x:%d,y:%g}", x, y)
    end

    local div = string.format("current%d", stats.alerts_cnt)
    local c = string.format(histogram_entry, div, "current", table.concat(cdata, ","), div);

    local prev = h.m:get_row(closest)
    local pdata = {}
    for x,y in ipairs(prev) do
        pdata[x] = string.format("{x:%d,y:%g}", x, y)
    end

    local div = string.format("closest%d", stats.alerts_cnt)
    local p = string.format(histogram_entry, div, string.format("closest index = %d", closest), table.concat(pdata, ","), div);
    stats.alerts[stats.alerts_cnt] = string.format("<h1>%s</h1>\n<span>Pearson's Correlation Coefficient:%g</span>\n%s%s", title, pcc, c, p)
end


local function output_histograms(stats)
    local sep = ""
    for k,o in pairs(histograms) do
        local ctime = o.submissions:current_time()
        if ctime <= stats.ns - histogram_samples * histogram_interval then
            histograms[k] = nil
        else
            stats.histogram_cnt = stats.histogram_cnt + 1
            stats.bucket_cnt = stats.bucket_cnt + o.buckets
            local sum, active = o.submissions:stats(nil, histogram_samples, "sum")
            add_to_payload(string.format(
                '%s"%s":{"buckets":%d,"type":%d,"created":%d,"submissions":%d,"active":%d',
                sep, escape_json(k), o.buckets, o.type, o.created, sum, active))
            local idx = get_last_complete_idx(o)
            local pcc, closest = o.m:pcc(idx)
            if pcc then
                add_to_payload(string.format(',"pcc":%g,"closest":%d', pcc, closest))
                if active >= alert_active
                and sum >= alert_submissions
                and pcc <= alert_pcc
                and stats.alerts_cnt < 25
                and not alert_ignore[k] then
                    stats.alerts_cnt = stats.alerts_cnt + 1
                    local title = escape_html(string.format("%s", tostring(k)))
                    debug_histogram(o, pcc, idx, closest, title, stats)
                end
            end
            add_to_payload("}")
            sep = ","
        end
    end
end


local function exponential_buckets(min, max, cnt)
    local b = {[0] = 0}
    if min == 0 then min = 1 end
    b[min] = 1
    lmax = math.log(max)
    for i=2, cnt - 1 do
        local lv = math.log(min)
        local lr = (lmax - lv) / (cnt - i)
        local rv = math.floor(math.exp(lv + lr) + 0.5)
        if rv > min then
            min = rv
        else
            min = min + 1
        end
        b[min] = i
    end
    return b
end


local function get_buckets(v)
    local min = v.range[1]
    local max = v.range[2]
    local cnt = v.bucket_count
    local bc = ebuckets[cnt]
    if not bc then
        bc = {}
        ebuckets[cnt] = bc
    end
    local mc = bc[min]
    if not mc then
        mc = {}
        bc[min] = mc
    end
    local b = mc[max]
    if not b then
        b = exponential_buckets(min, max, cnt)
        mc[max] = b
    end
    return b
end


local function find_histogram(ns, k, v)
    local h = histograms[k]
    if not h then
        h = {
            created = ns,
            buckets = v.bucket_count,
            type = v.histogram_type,
            m = matrix.new(histogram_samples, v.bucket_count),
            submissions = sats.new(histogram_samples, histogram_interval)
            }
        if v.histogram_type == 0 then
            h.bucket_idx = get_buckets(v)
        elseif v.histogram_type == 1 then
            local cnt = v.bucket_count
            local min = v.range[1]
            local max = v.range[2]
            h.bucket_size  = (max - min + 1) / (cnt - 2)
        end
        histograms[k] = h
    end

    local ptime = h.submissions:current_time()
    h.submissions:add(ns, 1)
    local ctime = h.submissions:current_time()
    local idx = math.floor(ctime / histogram_interval) % histogram_samples + 1
    if ctime ~= ptime then
        h.m:clear_row(idx)
    end
    return h, idx
end


local function linear(h, bucket)
    if bucket == 0 then return 0 end
    return math.floor(bucket / h.bucket_size + 0.5) + 1
end


function process_message()
    local ok, json = pcall(cjson.decode, read_message("Fields[payload.histograms]"))
    if not ok then return -1, json end

    local ns = read_message("Timestamp")
    for k,o in pairs(json) do
        local h, idx = find_histogram(ns, k, o)
        local cnt = 0
        for b,v in pairs(o.values) do
            cnt = cnt + v
        end
        for b,v in pairs(o.values) do
            local corrected  = v / cnt * 1000
            if corrected == corrected then
                local bucket = tonumber(b)
                if h.type == 0 then
                    bucket = h.bucket_idx[bucket] or 0
                elseif h.type == 1 then
                    bucket = linear(h, bucket)
                end
                h.m:add(idx, bucket + 1, corrected)
            end
        end
    end
    return 0
end


local viewer
local viewer1
local alert_name    = "alerts"
local alert_ext     = "html"
local schema_name   = "histograms"
local schema_ext    = "json"
local mg_template = [[
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<link href='css/metricsgraphics.css' rel='stylesheet' type='text/css' id='light'>
<script src="https://d3js.org/d3.v4.min.js"></script>
<script src='graphs/js/metricsgraphics.min.js'></script>
<body>
%s
</body>
</html>
]]

function timer_event(ns, shutdown)
    if shutdown then return end

    local stats = {
        ns              = ns,
        alerts          = {},
        alerts_cnt      = 0,
        histogram_cnt   = 0,
        bucket_cnt      = 0
    }

    add_to_payload("{\n")
    output_histograms(stats)
    add_to_payload(string.format(',"histogram_cnt":%d,\n"bucket_cnt":%d\n}', stats.histogram_cnt, stats.bucket_cnt))
    inject_payload(schema_ext, schema_name)

    if viewer then
        inject_payload("html", "viewer", viewer, alert.get_dashboard_uri(schema_name, schema_ext), viewer1)
        viewer = nil
        viewer1 = nil
    end

    if stats.alerts_cnt > 0 then
        inject_payload(alert_ext, alert_name, string.format(mg_template, table.concat(stats.alerts, "\n")))
        -- only one throttled alert for all histograms (the graph output contains all the issues)
        alert.send(alert_name, "pcc", string.format("graphs: %s\n", alert.get_dashboard_uri(alert_name, alert_ext)))
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
  for (key in schema) {
    var v = schema[key];
    if (typeof v === 'object') {
      v.name = key
      data.push(v);
    }
  }

  $('#histograms').DataTable( {
    data: data,
    order: [ [0, "asc"] ],
    columns: [
    { title: "Name", data: "name" },
    { title: "Buckets", data: "buckets" },
    { title: "Type", data: "type" },
    { title: "Submissions", data: "submissions" },
    { title: "Active Samples", data: "active" },
    { title: "PCC", data: "pcc", defaultContent: -2 },
    { title: "Closest", data: "closest", defaultContent: -1 }
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
