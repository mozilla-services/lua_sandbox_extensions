-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka IRC Alert Output Module

## Sample Configuration

To use the IRC module for alert output, include a configuration for the module
in the alert configuration. The value should be an array of connection specifications,
and the alerting module will create a connection for each one.

```lua
alert = {
    modules = {
        irc = {
            {
                nick        = "nick",
                server      = "irc.server",
                port        = 6697, -- optional, default shown
                channel     = "#hindsight",
                key         = "channelkey", -- optional, omit for no key required
            },
            {
                nick        = "othernick",
                server      = "irc.server2",
                port        = 6697, -- optional, default shown
                channel     = "#anotherchan",
            },
        },
    }
}
```

## Functions

### send

Function that actually composes and delivers the IRC alert

*Arguments*
- msg (table) - Heka alert message
- cfg (array) - module configuration variables extracted from the message

*Return*
- error (string/nil)
--]]

local module_name = string.match(..., "%.([^.]+)$")

local cfg = read_config("alert")
assert(type(cfg) == "table", "alert configuration must be a table")
assert(type(cfg.modules) == "table", "alert.modules configuration must be a table")

cfg = cfg.modules[module_name]
assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

local ipairs    = ipairs
local pairs     = pairs
local type      = type
local assert    = assert

local irc = require "irc"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local connections = {}

for _,v in ipairs(cfg) do
    assert(type(v.nick) == "string", "nick must be a string")
    assert(type(v.server) == "string", "server must be a string")
    assert(type(v.channel) == "string", "channel must be a string")
    if not v.port then v.port = 6697 end
    local k = v.server .. v.channel
    local c
    if v.key then
        c = irc.new(v.nick, v.server, v.port, v.channel, v.key)
    else
        c = irc.new(v.nick, v.server, v.port, v.channel)
    end
    assert(not connections[k], "duplicate server/channel configuration")
    connections[k] = c
end

function send(msg, mcfg)
    if not mcfg.target or not mcfg.target[1] then return nil end
    for k,v in pairs(connections) do
        if mcfg.target[1] == "*" or mcfg.target[1] == k then
            v:write_chan(msg.Fields[2].value[1])
        end
    end

    return nil
end

return M
