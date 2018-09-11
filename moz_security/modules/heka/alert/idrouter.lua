-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Alert IDRouter Lookup Module

idrouter provides identifier specific alert routing. It is intended to be used as a
lookup module in the Heka alert module.

The configuration of this module is used to control how alerts are routed.

The subjects configuration contains any user specific alerting parameters. Each entry
within subjects should be a key, which represents the standardized user identity string, and
a table containing configuration parameters.

At the least, each subjects entry should contain a mapfrom parameter. This is used to locate
the correct subject entry using the lookup data subject string. Where the lookup data subject
string matches an entry in mapfrom, this identity configuration will be used for the alert.

email and IRC alerts are currently supported. For each type, three categories exist.

Direct notification is used to determine how to route the alert directly to the user, and will
be used if senduser is set to true in lookup data.

Global notification is used when sendglobal is set to true in the lookup data.

Error notification is used when senderror is set to true in the lookup data.

A catchall setting can be set for each category for both IRC and email alerts. If the subject
entry does not specify a given category setting, the catchall will be used for the alert.

If lookup data is specified that does not contain a subject entry or does not match any known
subject, no direct alerts can be generated for the user -- however global and error alerts
may still fire depending on the lookup data settings.

Format strings are supported in a given category notification string. If %s is present in the
string value, the users standardized identity will be used in its place in the resulting
destination. If not specified, the string is used literally.

## Sample Configuration
```lua
alert = {
    lookup = "idrouter",
    modules = {
        idrouter = {
            subjects = {
                riker =  {
                    mapfrom = { "riker", "commanderriker" },
                },
                picard =  {
                    mapfrom = { "picard", "teaearlgreyhot" },
                    email = {
                        direct = "jean-luc@uss-enterprise"
                    }
                },
            },
            email = {
                direct = "manatee-%s@moz-svc-ops.pagerduty.com",
                global = "foxsec-dump+OutOfHours@mozilla.com"
            },
            irc = {
                global = "irc.server#target"
            }
        }
    }
}
```
--]]

local string    = require "string"
local table     = require "table"

local module_name = string.match(..., "%.([^.]+)$")

local cfg   = read_config("alert")
cfg         = cfg.modules[module_name]

local pairs     = pairs
local ipairs    = ipairs
local error     = error

assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

local M = {}
setfenv(1, M)

if cfg.subjects then
    for k,v in pairs(cfg.subjects) do
        if not v.mapfrom then error("subjects entry missing mapfrom") end
        if v.mapfrom then
            local nm = {}
            for i,w in ipairs(v.mapfrom) do
                nm[w] = true
            end
            v.mapfrom = nm
        end
    end
end


local function lalias(user)
    if not user then return nil, nil end
    local x = cfg.subjects
    if not x then return nil, nil end

    for k,v in pairs(x) do
        if v.mapfrom and v.mapfrom[user] then return k, v end
    end
    return nil, nil
end


local function vget(cat, el, u, udata)
    local use
    if udata then
        if udata[cat] then use = udata[cat][el] end
    end
    if not use then -- no user specific element, try cfg wide
        if cfg[cat] then use = cfg[cat][el] end
    end
    if not use then return nil end
    if cat == "email" then use = string.format("<%s>", use) end
    if string.find(use, "%%s") then
        if not u then return nil end
        return string.format(use, u)
    end
    return use
end


function get_message(id, summary, detail, ldata)
    local msg = {
        Type        = "alert",
        Payload     = detail,
        Severity    = 1,

        Fields = {
            { name = "id", value = id },
            { name = "summary", value = summary },
        }
    }
    local findex = 3

    local eur
    local eer
    local egr
    local iut
    local igt
    local iet

    local u, udata = lalias(ldata.subject)

    if u and ldata.senduser then
        eur = vget("email", "direct", u, udata)
        iut = vget("irc", "direct", u, udata)
    end

    if ldata.senderror then
        eer = vget("email", "error", u, udata)
        iet = vget("irc", "error", u, udata)
    end

    if ldata.sendglobal then
        egr = vget("email", "global", u, udata)
        igt = vget("irc", "global", u, udata)
    end

    if not eur and not eer and not egr
        and not iut and not igt and not iet then
        return nil -- no alert to send
    end

    if eur or eer or egr then -- email alerts
        local n = {}
        if eer then table.insert(n, eer) end
        if egr then table.insert(n, egr) end
        if eur then table.insert(n, eur) end
        msg.Fields[findex] = { name = "email.recipients", value = n }
        findex = findex + 1
    end

    -- only support a single irc target, prioritize user, error, then global
    local itv
    if iut then
        itv = iut
    elseif iet then
        itv = iet
    elseif igt then
        itv = igt
    end
    if itv then msg.Fields[findex] = { name = "irc.target", value = itv } end

    return msg
end

return M
