-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Tigerblood Module

Can be utilized by an analysis module to generate messages for the Tigerblood
output module. The send function expects a table containing violations to be forwarded
to the service.

## Sample configuration
```lua
tigerblood = {
    disabled = false, -- optional
}
```

## Functions

### send

Send a violation message to be processed by the Tigerblood output plugin.

*Arguments*
- violations - A table containing violation entries

*Return*
- sent (boolean) - true if sent, false if disabled or an invalid argument
--]]

-- Imports
local inject_message = inject_message
local pairs = pairs
local j = require "cjson"

local tb_cfg = read_config("tigerblood")

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {
    Type = "tigerblood",
    Fields = {},
}

function send(violations)
    if tb_cfg.disabled then
        return false
    end

    if not violations or #violations == 0 then
        return false
    end

    -- Ensure each entry in the violations table contains the correct fields
    for k,v in pairs(violations) do
        if not v["ip"] or not v["violation"] or not v["weight"] then
            return false
        end
    end

    -- Encode the violations as a JSON document and attach it to our fields
    msg.Fields[1] = { name = "violations", value = j.encode(violations) }
    inject_message(msg)

    return true
end

return M
