-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_hh_cms
--]]

require "string"

local msg = {
    Timestamp = 0,
    Logger = "input.hh_cms",
    Fields = {
        id = "",
    }
}

local testtable = {}

function add_tt_entry(k, n)
    testtable[k] = {}
    testtable[k].max = n
    testtable[k].cur = 0
end

function process_message()
    p = "10.0.0."
    for i = 1, 200 do
        add_tt_entry(string.format("%s%s", p, i), 80)
    end
    p = "10.0.1."
    for i = 1, 250 do
        add_tt_entry(string.format("%s%s", p, i), 150)
    end
    p = "10.0.2."
    for i = 1, 250 do
        add_tt_entry(string.format("%s%s", p, i), 80)
    end
    p = "10.0.3."
    for i = 1, 250 do
        add_tt_entry(string.format("%s%s", p, i), 80)
    end
    p = "192.168.1."
    for i = 1, 10 do
        add_tt_entry(string.format("%s%s", p, i), 1000)
    end
    p = "192.168.0."
    for i = 1, 20 do
        add_tt_entry(string.format("%s%s", p, i), 1500)
    end
    p = "10.0.4."
    for i = 1, 254 do
        add_tt_entry(string.format("%s%s", p, i), 80)
    end
    p = "10.0.5."
    for i = 1, 254 do
        add_tt_entry(string.format("%s%s", p, i), 60)
    end
    p = "10.0.6."
    for i = 1, 254 do
        add_tt_entry(string.format("%s%s", p, i), 95)
    end

    local finished = false
    while not finished do
        local sent = false
        for k,v in pairs(testtable) do
            if v.cur < v.max then
                msg.Fields.id = k
                inject_message(msg)
                v.cur = v.cur + 1
                sent = true
            end
        end
        if not sent then
            finished = true
        end
    end

    return 0
end
