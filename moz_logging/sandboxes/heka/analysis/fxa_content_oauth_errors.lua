-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Content OAuth Errors

Tracks and alerts on FXA OAuth errors.

## Sample Configuration
```lua
filename = 'fxa_content_oauth_errors.lua'
-- todo verify matcher
message_matcher = "Type == 'logging.fxa.content_server.docker.fxa-content'"
ticker_interval = 60
preserve_data = true

-- title = "FxA Content OAuth Errors" -- report title
-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents

alert = {
  disabled = false,
  prefix = true,
  throttle = 60,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
}
```
--]]
require "circular_buffer"
require "string"
require "os"
require "table"

local alert       = require "heka.alert"
local title       = read_config("title") or "FxA Content OAuth Errors"
local rows        = read_config("rows") or 1440
local sec_per_row = read_config("sec_per_row") or 60

data = circular_buffer.new(rows, 3, sec_per_row)
local INVALID_RESULT          = data:set_header(1, "RESULT")
local INVALID_RESULT_REDIRECT = data:set_header(2, "REDIRECT")
local INVALID_RESULT_CODE     = data:set_header(3, "CODE")
local alert_template = [[
Terrifying client metrics OAuth error!
Errors:
%d INVALID_RESULT - oauth.1001 - OAuth result is missing.
%d INVALID_RESULT_REDIRECT - oauth.1002 - OAuth result is available, but is missing redirect field.
%d INVALID_RESULT_CODE - oauth.1003 - OAuth code in result's redirect is missing or invalid.

Events: %s
]]

function process_message ()
    local ts = read_message("Timestamp")
    local i = 0
    local e = read_message("Fields[events]", 0, i)

    events = {}
    local r, rr, rc = 0, 0, 0

    while e ~= nil do
        table.insert(events, e)
        if e:match("error.*oauth.1001") then
            data:add(ts, INVALID_RESULT, 1)
            r = r + 1
        elseif e:match("error.*oauth.1002") then
            data:add(ts, INVALID_RESULT_REDIRECT, 1)
            rr = rr + 1
        elseif e:match("error.*oauth.1003") then
            data:add(ts, INVALID_RESULT_CODE, 1)
            rc = rc + 1
        end

        i = i + 1
        e = read_message("Fields[events]", 0, i)
    end

    if r + rr + rc > 0 then
        if not alert.throttled(title) then
            alert.send(title, "terrifying",
                       string.format(alert_template, r, rr, rc, table.concat(events, ", ")))
        end
    end

    return 0
end

function timer_event(ns)
    inject_payload("cbuf", title, data)
end
