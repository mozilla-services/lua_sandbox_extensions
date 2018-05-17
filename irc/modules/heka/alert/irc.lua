-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka IRC Alert Configuration Module

## Sample Configuration
```lua
alert = {
    modules = {
        irc = { channel_output = true } -- if true, write alerts to channel
    }
}

```
--]]

local module_name = string.match(..., "%.([^.]+)$")

local cfg = read_config("alert")
cfg = cfg.modules[module_name]
assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

local co = cfg.channel_output
if type(co) ~= "boolean" then
    error("channel_output must be boolean")
end

return {{name = module_name .. ".channel_output", value = co}}
