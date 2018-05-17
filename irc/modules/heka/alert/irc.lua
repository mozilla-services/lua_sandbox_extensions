-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka IRC Alert Configuration Module

The target configuration specifies which server/channel should receive the
alert message, in format "<server><channel>". A * can be used to indicate that
all configured connections in the alert module should receive the alert.

## Sample Configuration
```lua
alert = {
    modules = {
        irc = { target = "irc.server#channel" } -- target for messages, * for all
    }
}

```
--]]

local module_name = string.match(..., "%.([^.]+)$")

local cfg = read_config("alert")
cfg = cfg.modules[module_name]
assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

local co = cfg.target
if type(co) ~= "string" then
    error("target must be string")
end

return {{name = module_name .. ".target", value = co}}
