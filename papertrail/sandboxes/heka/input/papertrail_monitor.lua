-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Hindsight papertrail stall monitor

Reads in the hindsight.cp to make sure papertrail checkpoint is advancing.
Occasionally the HTTPS request fails to timeout and the plugin hangs
https://stackoverflow.com/questions/23568535/lua-http-request-timeout-hang

This is a stop gap measure to keep the data flowing

## Sample Configuration
```lua
filename = "papertrail_monitor.lua"
ticker_interval = 1800
preserve_data = false

plugin_name = "worker_metrics"
```
--]]
require "io"
require "os"
require "string"

local plugin_name       = read_config("plugin_name") or error "plugin_name must be set"
local output_path       = read_config("output_path")
local sandbox_run_path  = read_config("sandbox_run_path")
local sandbox_load_path = read_config("sandbox_load_path")

local prev_cp = nil

local match_name = string.format("'input%%.%s'", plugin_name)
function process_message()
    local fh = io.open(output_path .. "/hindsight.cp")
    if not fh then return 0 end -- file not available yet

    local curr_cp = nil
    for line in fh:lines() do
        if line:match(match_name) then
            curr_cp = line:match("= '(%d+)'")
            break
        end
    end
    fh:close()

    if prev_cp and prev_cp == curr_cp then
        local cmd = string.format("cp %s/input/%s.cfg %s/input/", sandbox_run_path, plugin_name, sandbox_load_path)
        local rv = os.execute(cmd)
        if rv ~= 0 then
            print("error", cmd)
        else
            print("papertrail stalled, restarting", cmd)
        end
    end
    prev_cp = curr_cp
    return 0
end
