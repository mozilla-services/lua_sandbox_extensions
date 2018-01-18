-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local cfg ={
    geoip_heka = {
        test = true,
        lookup = {city = "_city", country_code = "_country"},
    }
}

function read_config(k)
    return cfg[k]
end

local string = require "string"
local gh = require "geoip.heka"

local tests = {
    {{}, "remote_addr", nil},
    {{Fields = {}}, "remote_addr", {}},
    {{Fields = {remote_addr = "foobar"}}, "remote_addr", {remote_addr = "foobar"}},
    {{Fields = {remote_addr = "192.168.1.1"}}, "remote_addr", {remote_addr = "192.168.1.1"}},
    {{Fields = {remote_addr = "192.168.1.2"}}, "other_addr", {remote_addr = "192.168.1.2"}},
    {{Fields = {remote_addr = "192.168.1.2"}}, "remote_addr", {remote_addr = "192.168.1.2", remote_addr_city = "Mountain View", remote_addr_country = "US"}},
    {{Fields = {remote_addr = 7}}, "remote_addr", {remote_addr = 7}},
}

local function verify_table(idx, t, expected)
    if t == nil and expected ~= nil then
        error(string.format("test: %d failed Fields not nil", idx))
    end
    if not t then return end

    for k,r in pairs(t) do
        local e = expected[k]
        if e ~= r then
            error(string.format("test: %d field: %s expected: %s received: %s", idx, k, tostring(e), tostring(r)))
        end
    end
end

for i,v in ipairs(tests) do
    gh.add_geoip(v[1], v[2])
    verify_table(i, v[1].Fields, v[3])
end

cfg.geoip_heka.remove_original_field = true
local msg = {Fields = {remote_addr = "192.168.1.2"}}
gh.add_geoip(msg, "remote_addr")
verify_table(99, msg.Fields, tests[6][3])
assert(not msg.Fields.remote_addr)
