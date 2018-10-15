-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Histogram Module

## Functions

### create

Creates a histogram table with the expected schema.

*Arguments*
- rows (integer) - Number of rows in the histogram matrix
- ebuckets (nil/table) - Cache for the exponential buckets hash

*Return*
- histograms (table)


### clear_row

Clears the specified row in all histograms.

*Arguments*
- histograms (table) - Histograms data structure
- rows (integer) - Row index to clear

*Return*
- none

### process

Process the telemetry histogram JSON and updates the histogram data structure.

*Arguments*
- ns (integer) - Nanoseconds since Jan 1 1970
- json (table) - Telemetry histogram data structure
- histograms (table) - Histogram analysis data structure
- row (integer) - Hintogram row to apply the updates to

*Return*
- none

### output

Runs the histogram analysis and output the Histograms data structure as JSON.

*Arguments*
- histograms (table) - Histograms data structure
- row (integer) - Histogram row to analyze
- graphs (array) - Collection of debug graphs

*Return*
- none (all output is written to the payload buffer)

### alert

Turn the graphs array into a dashboard display and generate an alert linking
back to it when applicable.

*Arguments*
- graphs (array) - Collection of debug graphs

*Return*
- none

### output_viewer_html(schema_name, schema_ext)

Outputs the HTML viewer for the histogram data an the first invocation.

*Arguments*
- name (string) - Data file that this viewer will load
- extension (string) - Data file extension that this viewer will load

*Return*
- none


### get_exponential_buckets

Takes an exponential histogram specification and returns the value to bucket
index mapping.

*Arguments*
- min (integer) - Minimum bucket value
- max (integer) - Maximum bucket value
- cnt (integer) - Number of buckets
- cache (nil/table) - Cache for the exponential buckets hash

*Return*
- buckets (hash) - Hash of bucket values to index mapping
--]]

-- Imports
local ha            = require "heka.alert"
local escape_html   = require "lpeg.escape_sequences".escape_html
local escape_json   = require "lpeg.escape_sequences".escape_json
local math          = require "math"
local matrix        = require "streaming_algorithms.matrix"
local string        = require "string"
local table         = require "table"

local ipairs    = ipairs
local pairs     = pairs
local tonumber  = tonumber
local tostring  = tostring
local type      = type

local add_to_payload    = add_to_payload
local inject_payload    = inject_payload
local ticker_interval   = read_config("ticker_interval")

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local alert_pcc             = ha.get_threshold("pcc") or 0.3
local alert_submissions     = ha.get_threshold("submissions") or 1000
local alert_active          = ha.get_threshold("active") or 3600
local alert_ignore          = ha.get_threshold("ignore") or {}

--[[
histograms = {
   rows         = <number>, -- number of histograms rows to store in the matrix
   ebuckets     = <table>,  -- cache for the exponential bucket hash
   last_update  = <time_ns>,-- most recent entry (data timestamp driven, not clock driven)
   names = {
       <string> = {
           alerted          = <bool>,
           created          = <time_t>,
           updated          = <time_t>,
           bucket_count     = <integer>,
           histogram_type   = <integer>,
           buckets          = <hash>,   -- histogram_type == 0, return from get_exponential_buckets
           bucket_size      = <number>, -- histogram_type == 1, size of the linear histogram bucket
           submissions      = <streaming_algorithms.matrix>, -- submission count for each row
           data             = <streaming_algorithms.matrix>,
       }, -- ...
   },
--]]


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


local function find_histogram(ns, histograms, k, v)
    local h = histograms.names[k]
    local time_t = math.floor(ns / 1e9)
    if not h then
        local cnt = v.bucket_count
        h = {
            alerted = false,
            created = time_t,
            updated = 0,
            bucket_count = cnt,
            histogram_type = v.histogram_type,
            data = matrix.new(histograms.rows, cnt, "float"),
            submissions = matrix.new(histograms.rows, 1),
            }
        if v.histogram_type == 0 then
            local min = v.range[1]
            local max = v.range[2]
            h.buckets = get_exponential_buckets(min, max, cnt, histograms.ebuckets)
        elseif v.histogram_type == 1 then
            local min = v.range[1]
            local max = v.range[2]
            h.bucket_size  = (max - min + 1) / (cnt - 2)
        end
        histograms.names[k] = h
    end
    h.updated = time_t
    return h
end


local histogram_div = [[
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
local function debug_histogram_graph(h, pcc, row, closest, title, graphs)
    local cnt = #graphs
    local curr = h.data:get_row(row)
    local cdata = {}
    for x,y in ipairs(curr) do
        if y ~= y then y = 0 end
        cdata[x] = string.format("{x:%d,y:%g}", x, y)
    end

    local div = string.format("current%d", cnt)
    local c = string.format(histogram_div, div, "current", table.concat(cdata, ","), div);

    local prev = h.data:get_row(closest)
    local pdata = {}
    for x,y in ipairs(prev) do
        if y ~= y then y = 0 end
        pdata[x] = string.format("{x:%d,y:%g}", x, y)
    end

    div = string.format("closest%d", cnt)
    local p = string.format(histogram_div, div, string.format("closest index = %d", closest), table.concat(pdata, ","), div);
    graphs[cnt + 1] = string.format("<h1>%s</h1>\n<span>Pearson's Correlation Coefficient:%g</span>\n%s%s", title, pcc, c, p)
end


function create(rows, ebuckets)
    if not ebuckets then ebuckets = {} end
    return {rows = rows, ebuckets = ebuckets, last_update = 0, names = {}}
end


function clear_row(histograms, row)
    for k,v in pairs(histograms.names) do
      v.data:clear_row(row)
      v.submissions:clear_row(row)
      v.alerted = false
    end
end


function process(ns, json, histograms, row)
    if ns > histograms.last_update then histograms.last_update = ns end
    for k,o in pairs(json) do
        local h = find_histogram(ns, histograms, k, o)
        h.submissions:add(row, 1, 1)
        local cnt = 0
        for b,v in pairs(o.values) do
            cnt = cnt + v
        end
        for b,v in pairs(o.values) do
            local corrected  = v / cnt
            if corrected == corrected then
                local bucket = tonumber(b)
                if h.histogram_type == 0 then
                    bucket = h.buckets[bucket] or 0
                elseif h.histogram_type == 1 then
                    if bucket > 0 then
                        bucket = math.floor(bucket / h.bucket_size + 0.5) + 1
                    end
                end
                if bucket < 0 then
                    bucket = 0
                elseif bucket >= h.bucket_count then
                    bucket = h.bucket_count - 1
                end
                h.data:add(row, bucket + 1, corrected)
            end
        end
    end
end


function output(histograms, row, graphs)
    local sep = ""
    local last_update = histograms.last_update / 1e9
    for hn, t in pairs(histograms.names) do
        if  last_update - t.updated > 86400 then
            histograms.names[hn] = nil
        else
            local submissions = t.submissions:get(row, 1)
            add_to_payload(string.format('%s"%s":{"alerted":%s,"created":%d,"updated":%d,"bucket_count":%d,"histogram_type":%d,"submissions":%d', sep, escape_json(hn), tostring(t.alerted), t.created, t.updated, t.bucket_count, t.histogram_type, submissions))
            local pcc, closest = t.data:pcc(row)
            if pcc then
                add_to_payload(string.format(',"pcc":%g,"closest_row":%d', pcc, closest))
                if submissions >= alert_submissions
                and pcc <= alert_pcc
                and not t.alerted
                and t.updated - t.created > alert_active
                and #graphs < 25
                and not alert_ignore[hn] then
                    local alert = false
                    for i=1, histograms.rows do
                        -- confirm there is at least one other row with the minimum number of submissions
                        if i ~= row and t.submissions:get(i, 1) >= alert_submissions then
                            alert = true
                            break
                        end
                    end
                    if alert then
                        t.alerted = true
                        debug_histogram_graph(t, pcc, row, closest, escape_html(tostring(hn)), graphs)
                    end
                end
            end
            add_to_payload("}")
            sep = ","
        end
    end
end


local alert_name    = "alerts"
local alert_ext     = "html"
local html_fmt = [[
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
function alert(graphs)
    if #graphs > 0 then
        inject_payload(alert_ext, alert_name, string.format(html_fmt, table.concat(graphs, "\n")))
        ha.send(alert_name, "pcc", string.format("graphs: %s\n", ha.get_dashboard_uri(alert_name, alert_ext)))
    end
end


function get_exponential_buckets(min, max, cnt, cache)
    local b
    if cache then
        local bc = cache[cnt]
        if not bc then
            bc = {}
            cache[cnt] = bc
        end
        local mc = bc[min]
        if not mc then
            mc = {}
            bc[min] = mc
        end
        b = mc[max]
        if not b then
            b = exponential_buckets(min, max, cnt)
            mc[max] = b
        end
    else
        b = exponential_buckets(min, max, cnt)
    end
    return b
end


local histogram_viewer = [[
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

local histogram_viewer1 =
[[', load);">
<div>
    <h1>Histograms</h1>
    <table id="histograms" width="100%">
    </table>
</div>
</body>
</html>
]]

function output_viewer_html(name, extension)
    if histogram_viewer then
        inject_payload("html", "viewer", histogram_viewer, ha.get_dashboard_uri(name, extension), histogram_viewer1)
        histogram_viewer = nil
        histogram_viewer1 = nil
    end
end

return M
