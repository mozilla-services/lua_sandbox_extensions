-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka iprepd Module

Can be utilized by an analysis module to generate messages for the iprepd
output module. The send function expects a table containing violations to be forwarded
to the violations endpoint of the iprepd service (e.g., /violations/).

## Functions

### send

Send a violation message to be processed by the iprepd output plugin.

The violations argument should be an array containing tables with a violation
and ip value set.

```lua
{
    { ip = "192.168.1.1", violation = "fxa:request.check.block.accountStatusCheck" },
    { ip = "10.10.10.10", violation = "fxa:request.check.block.accountStatusCheck" }
}
```

*Arguments*
- violations - A table containing violation entries

*Return*
- sent (boolean) - true if sent, false if invalid argument
--]]

local jenc           = require "cjson".encode

local inject_message = inject_message
local pairs          = pairs
local type           = type
local error          = error

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {
    Type = "iprepd",
    Fields = {},
}

function send(violations)
    if not violations or type(violations) ~= "table" then
        return false
    end

    local vcnt = 0
    for k,v in pairs(violations) do
        if not v.ip or not v.violation then
            return false
        end
        vcnt = vcnt + 1
    end
    if vcnt == 0 then
        return false
    end

    msg.Fields[1] = { name = "violations", value = jenc(violations) }
    inject_message(msg)

    return true
end

return M
