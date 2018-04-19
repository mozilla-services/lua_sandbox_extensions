-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Extensions for LPeg Modules

This module is intended to be used with another IO module such as a decoder to
extend the message with additional transformations prior to injection.

## Functions

### add_normalized_user_agent

Given a Heka message add the normalized user agent entries based on the
specified field name.

*Arguments*
- msg (table) - original message
- field_name (string) - field name in the message to lookup

*Return*
- none - the message is modified in place or an error is thrown
The added fields will have the same name as `field_name` with suffixes of
"_browser", "_version" and "_os"

#### Configuration Options
```lua
lpeg_heka = {
    user_agent_normalized_field_name = "user_agent", -- set to override the original field name prefix
    user_agent_remove = true, -- remove the user agent field after a successful normalization
}

### set_(uuid|timestamp|logger|hostname|type|envversion|payload|severity|pid)

Set the specificed header to the field value and removes the field.

*Arguments*
- msg (table) - original message
- field_name (string) - field name in the message to lookup

*Return*
- none - the message is modified in place or an error is thrown

### remove_payload

Remove the `Payload` header which is set by default when using a grammar decoder.

*Arguments*
- msg (table) - original message
- field_name (string) - ignored

*Return*
- none - the message is modified in place or an error is thrown

```
--]]
local module_name = ...
local module_cfg  = require "string".gsub(module_name, "%.", "_")
local cfg         = read_config(module_cfg) or {}
local clf         = require "lpeg.common_log_format"

local type = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

function add_normalized_user_agent(msg, field_name)
    local value = msg.Fields[field_name]
    if type(value) ~= "string" then return end

    local nfn = cfg.user_agent_normalized_field_name or field_name
    local browser, version, os = clf.normalize_user_agent(value)
    msg.Fields[nfn .. "_browser"] = browser
    msg.Fields[nfn .. "_version"] = version
    msg.Fields[nfn .. "_os"]      = os
    if browser and cfg.user_agent_remove then
        msg.Fields[field_name] = nil
    end
end


function set_uuid(msg, field_name)
    msg.Uuid = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_timestamp(msg, field_name)
    msg.Timestamp = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_logger(msg, field_name)
    msg.Logger = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_hostname(msg, field_name)
    msg.Hostname = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_type(msg, field_name)
    msg.Type = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_envversion(msg, field_name)
    msg.EnvVersion = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_payload(msg, field_name)
    msg.Payload = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_severity(msg, field_name)
    msg.Severity = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function set_pid(msg, field_name)
    msg.Pid = msg.Fields[field_name]
    msg.Fields[field_name] = nil
end


function remove_payload(msg)
    msg.Payload = nil
end

return M
