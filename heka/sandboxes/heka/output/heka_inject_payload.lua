-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "lfs"
require "os"
require "string"
local escape_html = require "lpeg.escape_sequences".escape_html

--[[
# Message Payload Output

Outputs the message payload to the configured directory. The output filename is
`output_dir`/`Logger.Fields[payload_name]`.`Fields[payload_type]`
and the contents are the message `Payload`.

## Sample Configuration
```lua
filename        = "heka_inject_payload.lua"
message_matcher = "Type == 'inject_payload'"
ticker_interval = 86400 -- output prune interval
read_queue      = "analysis"

-- location where the payload is written (e.g. make them accessible from a web
-- server for external consumption)
output_dir      = "/var/tmp/hindsight/payload"
```
--]]

local output_path   = read_config("output_path") -- provided by Hindsight
local output_dir    = read_config("output_dir") or "/var/tmp/hindsight/payload"
local graphs_dir    = output_dir .. "/graphs"
local install_path  = read_config("sandbox_install_path")

local cmd = string.format("mkdir -p %s/js", graphs_dir)
local ret = os.execute(cmd)
if ret ~= 0 then
    error(string.format("mkdir ret: %d, cmd: %s", ret, cmd))
end

local function copy_files()
    local files = {"cbuf.js", "dygraph-combined.js"}
    for i, v in ipairs(files) do
        local cmd = string.format('cp "%s" "%s"',
                                  string.format("%s/output/%s", install_path, v),
                                  string.format("%s/js/%s", graphs_dir, v));
        local ret = os.execute(cmd)
        if ret ~= 0 then
            error(string.format("copy ret: %d, cmd: %s", ret, cmd))
        end
    end
end
copy_files()

local payload       = read_message("Payload", nil, nil, true)
local graphs        = {}
local html_template = [[
<!DOCTYPE html>
<html>
<head>
    <script src="js/dygraph-combined.js"  type="text/javascript"></script>
    <script src="js/cbuf.js"  type="text/javascript"></script>
</head>
<body onload="heka_load_cbuf('../%s', heka_load_cbuf_complete);">
<p id="title" style="text-align: center">%s</p>
<p id="range" style="text-align: center"></p>
</body>
</html>
]]

local function output_html(cbfn, logger, pn, nlogger, npn)
    local fn = string.format("%s/%s.%s.html", graphs_dir, nlogger, npn)
    local fh, err = io.open(fn, "w")
    if err then return err end

    local title = escape_html(string.format("%s [%s]", logger, pn))
    fh:write(string.format(html_template, cbfn, title))
    fh:close()
end

function process_message()
    local logger = read_message("Logger") or ""

    local pn = read_message("Fields[payload_name]") or ""
    if type(pn) ~= "string" then return -1, "invalid payload_name" end

    local pt = read_message("Fields[payload_type]")
    if type(pt) ~= "string" then return -1, "invalid payload_type" end

    local npn = string.gsub(pn, "[^%w%.]", "_")
    local npt = string.gsub(pt, "%W", "_")
    local nlogger = string.gsub(logger, "[^%w%.]", "_")
    local cbfn = string.format("%s.%s.%s", nlogger, npn, npt)
    local fn = string.format("%s/%s", output_dir, cbfn)

    if pt == "cbuf" and not graphs[fn] then
        local err = output_html(cbfn, logger, pn, nlogger, npn)
        if err then return -1, err end
        graphs[fn] = true
    end

    local fh, err = io.open(fn, "w")
    if err then return -1, err end

    fh:write(payload)
    fh:close()
    return 0
end


local function remove_inactive(active, dir)
    for fn in lfs.dir(dir) do
        local plugin = fn:match("^(analysis%..+)%.[^.]*%.[^.]+$")
        if plugin and not active[plugin] then
            os.remove(string.format("%s/%s", dir, fn))
        end
    end
end

function timer_event(ns, shutdown)
    if shutdown then return end

    local fh = io.open(output_path .. "/utilization.tsv")
    if not fh then return end -- utilization file not available

    local active = {}
    for line in fh:lines() do
        local plugin = line:match("^(analysis%.[^\t]+)")
        if plugin then
            active[plugin] = true
        end
    end
    fh:close()

    remove_inactive(active, output_dir)
    remove_inactive(active, graphs_dir)
    graphs = {}
end
