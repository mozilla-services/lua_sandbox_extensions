-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Alert Output

Send alert messages to the specified end points

## Sample Configuration
```lua
filename        = "alert.lua"
message_matcher = "Type == 'alert'"

alert = {
    modules = {
        module_name = {
            -- see the io_modules alert.modules_name documentation for the configuration options
        },
    }
}
```
--]]

require "string"

local modules_cfg = read_config("alert")
assert(type(modules_cfg) == "table", "alert configuration must be a table")

modules_cfg = modules_cfg.modules
assert(type(modules_cfg) == "table", "alert.modules configuration must be a table")

for name,v in pairs(modules_cfg) do
    local ok, mod = pcall(require, "alert." .. name)
    if ok then
        modules_cfg[name] = mod
    else
        error(mod)
    end
end

function process_message()
    local rv = 0
    local err = nil
    local modules = {}

    local raw = read_message("raw")
    local msg = decode_message(raw)

    for i=3, #msg.Fields do
        v = msg.Fields[i]
        local name, var = string.match(v.name, "^(.+)%.(.+)")
        if not name then return -1, "invalid field name: " .. v.name end

        local mcfg = modules[name]
        if not mcfg then
            mcfg = {}
            modules[name] = mcfg
        end
        mcfg[var] = v.value
    end

    for name, mcfg in pairs(modules) do
        local mod = modules_cfg[name]
        if mod then
            local ok, serr = pcall(mod.send, msg, mcfg)
            if serr then
                rv = -1
                err = serr
            end
        else
            rv = -1
            err = string.format("alert module '%s' is not configured", name)
        end
    end
    return rv, err
end

function timer_event(ns)
    -- no op
end
