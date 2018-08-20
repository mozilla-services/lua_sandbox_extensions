-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Cloudtrail notifications

Analyze messages that are sent from AWS Cloudtrail and provide alerting notifications
on configured event matchers.

This sandbox expects raw Cloudtrail "Records", as sent from cloudtrail-streamer
(https://github.com/mozilla-services/cloudtrail-streamer) or similar.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure process_message_inject_limit is set appropriately, as if enabled process_event
will submit up to 2 messages (the alert, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_cloudtrail.lua"
message_matcher = "Type == 'logging.cloudtrail.lambda.cloudtrail.logs'"
ticker_interval = 0
process_message_inject_limit = 1

-- cloudtrail events to alert on (required)
events = {
    {
        description = "mfa disabled",
        resource = "requestParameters.userName",
        fields = {
            { "eventName", "^DeleteVirtualMFADevice$" },
        }
    },
    {
        description = "mfa disabled",
        resource = "requestParameters.userName",
        fields = {
            { "eventName", "^DeactivateMFADevice$" },
        }
    },
    {
        description = "access key created",
        resource = "requestParameters.userName",
        fields = {
            { "eventName", "^CreateAccessKey$" }
        }
    },
    {
        description = "IAM action in production account from console without mfa",
        fields = {
            { "eventSource", "^iam.amazonaws.com$" },
            { "recipientAccountId", "^1234567890$" },
            { "userIdentity.invokedBy", "^signin.amazonaws.com$" },
            { "userIdentity.sessionContext.attributes.mfaAuthenticated", "^false$" }
        }
    }
}

-- mapping of aws account ids to human-friendly names (optional)
aws_account_mapping = {
    ["5555555555"] = "dev",
    ["1234567890"] = "prod"
}

-- module makes use of alert output and needs a valid alert configuration
alert = {
    modules = { }
}

-- enable_metrics = false -- optional, if true enable secmetrics submission
```
--]]

require "cjson"

local alert = require "heka.alert"

local cfevents               = read_config("events")
local cfaccount_name_mapping = read_config("aws_account_mapping")

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end


function genpayload()
    local msg = decode_message(read_message("raw"))
    local p = {}
    for _, kvpair in ipairs(msg.Fields) do
        if #kvpair.value == 1 then
            p[kvpair.name] = kvpair.value[1]
        else
            p[kvpair.name] = kvpair.value
        end
    end
    return cjson.encode(p)
end

function get_account_name(account_id)
    if cfaccount_name_mapping then
        return cfaccount_name_mapping[account_id] or account_id
    end
    return account_id
end

function get_identity_name()
    local identity_type = read_message("Fields[userIdentity.type]")

    if identity_type == "IAMUser" then
        return read_message("Fields[userIdentity.userName]")
    elseif identity_type == "AssumedRole" then
        return read_message("Fields[userIdentity.sessionContext.sessionIssuer.userName]")
    elseif identity_type == "AWSService" then
        return read_message("Fields[userIdentity.invokedBy]")
    elseif identity_type == "AWSAccount" then
        return read_message("Fields[userIdentity.accountId]")
    end

    return nil
end

function process_message()
    local event_id   = read_message("Fields[eventID]")
    local account_id = read_message("Fields[recipientAccountId]")

    local det = {
        eventID = event_id,
        recipientAccountId = account_id
    }

    for _, event in ipairs(cfevents) do
        local match_counter = 0

        for _, field in ipairs(event.fields) do
            if not det[field[1]] then
                det[field[1]] = read_message(string.format("Fields[%s]", field[1]))
            end

            if det[field[1]] then
                if string.match(det[field[1]], field[2]) then
                    match_counter = match_counter + 1
                end
            end
        end

        if match_counter == #event.fields then
            local id = string.format("%s - %s", event.description, event_id)
            local s = string.format("%s in %s by %s", event.description, get_account_name(account_id), get_identity_name() or "unknown")
            if event.resource then
                r = read_message(string.format("Fields[%s]", event.resource))
                s = string.format("%s on %s", s, r or "unknown")
            end

            alert.send(id, s, genpayload())
            if secm then
                secm:inc_accumulator("total_count")
                secm:send()
            end
        end
    end
    return 0
end

function timer_event(ns)
    -- noop
end
