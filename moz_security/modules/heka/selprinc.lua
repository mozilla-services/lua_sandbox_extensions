-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Select Events with Principal Attributes

This modules provides a generic interface to specify a list of events to match that
contain information relevant to an action being undertaken by a principal (user). When
an event is matched, fields are extracted per the event configuration and a normalized
table is returned containing the relavent details from the event.

## Functions

### match

The match function can be called from with process_event to attempt to match the event
against the event configuration. The first event category where select_field matches
select_match will be parsed and a table structure will be returned, which will also
include the category of the event that matched.

For an event to successfully match, the subject_field, object_field, and sourceip_field
must be present in the message.

object_static can be specified instead of object_field in order to place a static object
value into the returned table instead of doing a field lookup to obtain the value.

If the subject_map configuration option is used in an event configuration, the value
extracted for the subject will be converted according to the subject_map table before
being returned.

The aux configuration within a given event category can be used to have the matcher return
additional extracted message fields in the returned table, but are not specifically required
and will be nil if they were not present in the event.

*Arguments*
- None

*Return*
- result (table, nil) - normalized table containing event fields, or nil of no match

## Configuration examples

```lua
heka_selprinc = {
    events = {
        ssh = {
            select_field     = "Fields[programname]",
            select_match     = "^sshd$",
            subject_field    = "Fields[user]",
            object_field     = "Hostname",
            -- object_static = "Ten Forward",
            sourceip_field   = "Fields[ssh_remote_ipaddr]",

            aux = {
                { "geocity", "Fields[ssh_remote_ipaddr_city]" },
                { "geocountry", "Fields[ssh_remote_ipaddr_country]" }
            }
        },
        awsconsole = {
            select_field     = "Fields[eventType]",
            select_match     = "^AwsConsoleSignIn$",
            subject_field    = "Fields[userIdentity.userName]",
            object_field     = "Fields[recipientAccountId]",
            sourceip_field   = "Fields[sourceIPAddress]",
            subject_map = {
                ["An admin user"]   = "admin",
                ["Commander Riker"] = "riker"
            }
        }
    }
}
```
--]]

local string        = require "string"

local module_name   = ...
local module_cfg    = string.gsub(module_name, "%.", "_")
local cfg           = read_config(module_cfg) or error(module_cfg .. " configuration not found")

assert(type(cfg.events) == "table", "invalid selprinc events configuration")
local cnt = 0
for _,v in pairs(cfg.events) do
    cnt = cnt + 1
    if not v.select_field or not v.select_match or not v.subject_field or not
        (v.object_field or v.object_static) or not v.sourceip_field then
        error("selprinc configuration missing required parameters")
    end
    if v.aux then
        for _,w in ipairs(v.aux) do
            if #w ~= 2 then error("aux element has incorrect length") end
        end
    end
end
if cnt == 0 then error("selprinc configuration contained no events") end

local pairs         = pairs
local ipairs        = ipairs
local type          = type
local read_message  = read_message

local M = {}
setfenv(1, M)

local function find_event_fields()
    for k,v in pairs(cfg.events) do
        local x = read_message(v.select_field)
        if x then if string.match(x, v.select_match) then return k,v end end
    end
end

local function subject_map(f, m)
    if not m or not f then return f end
    return m[f] or f
end

function match()
    et,ef = find_event_fields()
    if not et then return nil end

    ret = {
        category    = et,
        subject     = subject_map(read_message(ef.subject_field), ef.subject_map),
        object      = ef.object_static or read_message(ef.object_field),
        sourceip    = read_message(ef.sourceip_field),
    }
    if not ret.subject or not ret.object or not ret.sourceip then return nil end

    if ef.aux then
        for i,v in ipairs(ef.aux) do
            ret[v[1]] = read_message(v[2])
        end
    end

    return ret
end

return M
