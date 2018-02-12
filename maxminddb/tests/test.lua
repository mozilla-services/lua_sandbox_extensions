-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local cfg ={
    maxminddb_heka = {
        databases = {
            ["GeoIP2-City-Test.mmdb"] = {
                _city = {"city", "names", "en"},
                _country = {"country", "iso_code"}
            },
            ["GeoIP2-ISP-Test.mmdb"] = {
                _isp = {"isp"}
            },
        }
    }
}

function read_config(k)
    return cfg[k]
end

local string = require "string"
local gh = require "maxminddb.heka"

local tests = {
    {{}, "remote_addr", nil},
    {{Fields = {}}, "remote_addr", {}},
    {{Fields = {remote_addr = "foobar"}}, "remote_addr", {remote_addr = "foobar"}},
    {{Fields = {remote_addr = "192.168.1.1"}}, "remote_addr", {remote_addr = "192.168.1.1"}},
    {{Fields = {remote_addr = "216.160.83.56"}}, "other_addr", {remote_addr = "216.160.83.56"}},
    {{Fields = {remote_addr = "216.160.83.56"}}, "remote_addr", {
        remote_addr = "216.160.83.56",
        remote_addr_city = "Milton",
        remote_addr_country = "US",
        remote_addr_isp = "Century Link"}
    },
    {{Fields = {remote_addr = 7}}, "remote_addr", {remote_addr = 7}},
    {{Fields = {remote_addr = {value = "216.160.83.56", representation = "ipv4"}}},
        "remote_addr",
        {
            remote_addr = {value = "216.160.83.56", representation = "ipv4"},
            remote_addr_city = "Milton",
            remote_addr_country = "US",
            remote_addr_isp = "Century Link"
        }
    },
    {{Fields = {remote_addrs = {"216.160.83.56", "192.168.1.1"}}},
        "remote_addrs",
        {
            remote_addrs = {"216.160.83.56", "192.168.1.1"},
            remote_addrs_city = {"Milton", ""},
            remote_addrs_country = {"US", ""},
            remote_addrs_isp = {"Century Link", ""}
        }
    },
    {{Fields = {remote_addrs = {value = {"216.160.83.56", "192.168.1.1"}, representation = "ipv4"}}},
        "remote_addrs",
        {
            remote_addrs = {value = {"216.160.83.56", "192.168.1.1"}, representation = "ipv4"},
            remote_addrs_city = {"Milton", ""},
            remote_addrs_country = {"US", ""},
            remote_addrs_isp = {"Century Link", ""}
        }
    },
    {{Fields = {remote_addrs = {"192.168.1.3", "192.168.1.4"}}},
        "remote_addrs",
        {
            remote_addrs = {"192.168.1.3", "192.168.1.4"}
        }
    },
}

local function verify_field(idx, k, expected, received)
    local ev = expected
    local rv = received
    if ev.value then
        if ev.representation ~= rv.representation then
            error(string.format("test: %d field: %s representation expected: %s received: %s",
                                idx, k, tostring(ev.representation), tostring(rv.represntation)))
        end
        ev = ev.value
        rv = rv.value
    end

    if type(ev) == "table" then
        for i,v in ipairs(ev) do
            if v ~= rv[i] then
                error(string.format("test: %d field: %s idx: %d expected: %s received: %s",
                                    idx, k, i, tostring(v), tostring(rv[i])))
            end
        end
    elseif ev ~= rv then
        error(string.format("test: %d field: %s expected: %s received: %s",
                            idx, k, tostring(ev), tostring(rv)))
    end
end


local function verify_msg_fields(idx, expected, received)
    if expected == nil and received ~= nil then
        error(string.format("test: %d failed Fields not nil", idx))
    end
    if not expected then return end

    for k,e in pairs(expected) do
        local r = received[k]
        local etyp = type(e)
        local rtyp = type(r)
        if etyp ~= rtyp then
            error(string.format("test: %d field: %s type expected: %s received: %s",
                                idx, k, etyp, rtyp))
        end
        if etyp == "table" then
            verify_field(idx, k, e, r)
        elseif e ~= r then
            error(string.format("test: %d field: %s expected: %s received: %s",
                                idx, k, tostring(e), tostring(r)))
        end
    end
    if idx > 0 then
        verify_msg_fields(-idx, received, expected)
    end
end

for i,v in ipairs(tests) do
    gh.add_geoip(v[1], v[2])
    verify_msg_fields(i, v[3], v[1].Fields)
end


local t = cfg.maxminddb_heka.databases["GeoIP2-City-Test.mmdb"]
t._country = nil
cfg.maxminddb_heka.remove_original_field = true
local msg = {Fields = {remote_addr = "216.160.83.56"}}
gh.add_geoip(msg, "remote_addr")
verify_msg_fields(98, {remote_addr_city = "Milton", remote_addr_isp = "Century Link"}, msg.Fields)
cfg.maxminddb_heka.remove_original_field = false

t[""] = t._city -- replace the original field with city
t._city = nil
local msg = {Fields = {remote_addr = "216.160.83.56"}}
gh.add_geoip(msg, "remote_addr")
verify_msg_fields(99, {remote_addr = "Milton", remote_addr_isp = "Century Link"}, msg.Fields)
