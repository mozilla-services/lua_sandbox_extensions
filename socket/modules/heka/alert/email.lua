-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Email Alert Configuration Module

Returns a Heka Message field named 'email.recipients' containing the alert
email distribution list.


## Sample Configuration
```lua
alert = {
    modules = {
        email = {
            recipients = {"foo@example.com"},
	    -- footer = "example footer" -- optional
        }
    }
}

```
--]]

local module_name = string.match(..., "%.([^.]+)$")

local cfg = read_config("alert")
cfg = cfg.modules[module_name]
assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

local r = cfg.recipients
if type(r) ~= "table" or #r == 0 then
    error("recipients must be an array")
end

for i, v in ipairs(r) do
    if type(v) ~= "string" then
        error("recipients must be strings")
    end
    r[i] = string.format("<%s>", v)
end

return {{name =  module_name .. ".recipients", value = r}}
