-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_http_error_rate
--]]

require "string"

local msg = {
    Timestamp = 0,
    Logger = read_config("logger"),
    Fields = {
        id      = "",
        code    = 0,
    }
}

local testtable = {}

function add_tt_entry(k, n, c)
    testtable[k] = {
        max     = n,
        cur     = 0,
        code    = c,
    }
end

function process_message()
    for i = 1, 200 do
        add_tt_entry(string.format("10.0.0.%d", i), 100, 200)
    end
    for i = 1, 200 do
        add_tt_entry(string.format("10.0.1.%d", i), 60, 500)
    end
    add_tt_entry("10.0.2.10", 75, 403)
    add_tt_entry("10.0.2.11", 25, 404)
    add_tt_entry("10.0.2.12", 500, 400)

    local finished = false
    while not finished do
        local sent = false
        for k,v in pairs(testtable) do
            if v.cur < v.max then
                msg.Fields.id = k
                msg.Fields.code = v.code
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
