-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka IRC Alert Output Module

## Sample Configuration

```lua
alert = {
    modules = {
        irc = {
            nick        = "nick",
            server      = "irc.server",
            port        = 6697, -- optional, default shown
            channel     = "#hindsight",
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

assert(type(cfg.nick) == "string", "alert.irc.nick must be a string")
assert(type(cfg.server) == "string", "alert.irc.server must be a string")
assert(type(cfg.channel) == "string", "alert.irc.channel must be a string")
if not cfg.port then cfg.port = 6697 end

local irc = require "irc"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local ircconn = irc.new(cfg.nick, cfg.server, cfg.port, cfg.channel)

function send(msg, mcfg)
    if not mcfg.channel_output[1] then return nil end

    ircconn:write_chan(msg.Fields[2].value[1])
    return nil
end

return M
