-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Unique Item Counter

Counts the number of unique items per configurable time period e.g. active daily users by uid.

## Sample Configuration
```lua
filename = 'moz_logging_unique_items.lua'
message_matcher = "Type == 'logging.fxa.auth_server.nginx.access'"
ticker_interval = 60
preserve_data = true

-- message_variable (string, required)
-- The Heka message variable containing the item to be counted.
message_variable = "Fields[http_x_forwarded_for]"

-- title (string, optional, default "Estimated Unique Daily *message_variable*")
-- The graph title for the cbuf output.
-- title = nil

-- enable_delta (bool, optional, default false)
-- Specifies whether or not this plugin should output cbuf deltas
-- enable_delta = false

-- rows (uint, optional, default 365)
-- The numbers of rows or time periods to keep in history.
-- rows = 365

-- seconds_per_row (uint, optional, default 86400)
-- The number of seconds per row or time period, before switching to the next row.
-- seconds_per_row = 86400

-- preservation_version (uint, optional, default 0)
-- If `preserve_data = true` then this value should be incremented every time
-- the `rows` or 'seconds_per_row' configuration is changed to prevent the
-- plugin from failing to start during data restoration.
-- preservation_version = 0
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0

require "hyperloglog"
require "circular_buffer"
require "math"
require "string"

local message_variable  = read_config("message_variable") or error("message_variable configuration must be specified")
local title             = read_config("title") or "Estimated Unique Daily " .. message_variable
local enable_delta      = read_config("enable_delta") or false
local rows              = read_config("rows") or 365
local seconds_per_row   = read_config("seconds_per_row") or 60 * 60 * 24

active_period  = 0
hll         = hyperloglog.new()
active      = circular_buffer.new(rows, 1, seconds_per_row)
local USERS = active:set_header(1, message_variable:match("^Fields%[([^%]]+)%]") or message_variable)
local floor = math.floor

function process_message ()
    local ts = read_message("Timestamp")

    local period = floor(ts / (seconds_per_row * 1e9))
    if period < active_period  then
        return 0 -- too old
    elseif period > active_period then
        active_period = period
        hll:clear()
    end

    local item = read_message(message_variable)
    if not(type(item) == "string" or type(item) == "number") then return -1 end

    if hll:add(item) then
        active:set(ts, USERS, hll:count())
    end

    return 0
end

function timer_event(ns)
    inject_payload("cbuf", title, active:format("cbuf"))
    if enable_delta then
        inject_payload("cbufd", title, active:format("cbufd"))
    end
end


