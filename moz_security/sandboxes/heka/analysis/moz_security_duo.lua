-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Duo notifications

Analyze messages generated from the Duo logging API and provide alerting notifications
on various event types.

This sandbox expects Duo messages generated in the Mozlog format, as occurs with the
duopull-lambda function (https://github.com/mozilla-services/duopull-lambda).

## Sample Configuration
```lua
filename = "moz_security_duo.lua"
message_matcher = "Logger == 'input.duopull_lambda_duopull_logs'"
ticker_interval = 0
preserve_data = false

bypass_create = false -- bypass code generation
user_create = false -- new user creation
auth_phone_fail = false -- telephony factor, request failure
auth_fraud = false -- duo fraud marker
admin_2fa_error = false -- admin console 2fa error
integration_addup = false -- integration key add/change
admin_addup = false -- console administrator add/change
anomalous_push = false -- duo anomalous push notification

-- module makes use of alert output and needs a valid alert configuration
alert = {
    modules = { }
}
```
--]]

require "cjson"

local alert = require "heka.alert"

local cfgbypasscreate   = read_config("bypass_create")
local cfgusercreate     = read_config("user_create")
local cfgauthphonefail  = read_config("auth_phone_fail")
local cfgauthfraud      = read_config("auth_fraud")
local cfgadmin2faerr    = read_config("admin_2fa_error")
local cfgintegaddup     = read_config("integration_addup")
local cfgadminaddup     = read_config("admin_addup")
local cfganompush       = read_config("anomalous_push")

-- supplementary fields for merge into the alert payload other than
-- event_description which has special handling
local sfields = {
    "event_device",
    "event_integration",
    "event_ip",
    "event_location_city",
    "event_location_country",
    "event_location_state",
    "event_timestamp",
    "event_description_uname",
    "event_description_notes",
    "event_description_realname",
    "event_description_status",
    "event_description_email",
    "event_description_error",
    "event_description_ip_address",
    "event_description_factor"
}

function genpayload(det)
    for _,v in ipairs(sfields) do
        local vk = string.format("Fields[%s]", v)
        det[v] = read_message(vk)
    end
    return cjson.encode(det)
end

function process_message()
    local det = {
        event_object    = read_message("Fields[event_object]"),
        event_action    = read_message("Fields[event_action]"),
        event_factor    = read_message("Fields[event_factor]"),
        event_reason    = read_message("Fields[event_reason]"),
        event_username  = read_message("Fields[event_username]"),
        event_result    = read_message("Fields[event_result]")
    }
    local s = nil

    if cfgbypasscreate and
        (det.event_object and det.event_action == "bypass_create") then
        s = string.format("duo bypass code creation for user %s", det.event_object)
    elseif cfgusercreate and
        (det.event_object and det.event_action == "user_create") then
        s = string.format("duo new user created %s", det.event_object)
    elseif cfgauthphonefail and det.event_username and
        (det.event_factor == "Phone Call" and
        det.event_result == "FAILURE" and
        (det.event_reason == "No response" or det.event_reason == "No keys pressed")) then
        s = string.format("duo phone call factor rejected for user %s", det.event_username)
    elseif cfgauthfraud and det.event_username and
        det.event_result == "FRAUD" then
        s = string.format("duo fraud flag on authentication for user %s", det.event_username)
    elseif cfgadmin2faerr and det.event_username and
        det.event_action == "admin_2fa_error" then
        s = string.format("duo admin_2fa_error on console access for user %s", det.event_username)
    elseif cfgintegaddup and det.event_username and
        (det.event_action == "integration_create" or det.event_action == "integration_update") then
        s = string.format("duo admin integration added or modified by user %s", det.event_username)
    elseif cfgadminaddup and det.event_username and det.event_object and
        (det.event_action == "admin_create" or det.event_action == "admin_update") then
        s = string.format("duo admin user %s added or modified by user %s", det.event_object,
            det.event_username)
    elseif cfganompush and det.event_username then
        s = string.format("duo anomalous push recorded for user %s", det.event_username)
    end

    if s then
        alert.send(s, s, genpayload(det))
    end
    return 0
end

function timer_event(ns)
    -- noop
end
