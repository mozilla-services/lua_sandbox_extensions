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
local test = require "test_verify_message"

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


for i,v in ipairs(tests) do
    gh.add_geoip(v[1], v[2])
    test.verify_msg_fields(v[3], v[1].Fields, i, true)
end


cfg.maxminddb_heka.xff = "last"
local tests_last = {
    {{Fields = {xff_addrs = "192.168.1.1, 216.160.83.56"}},
        "xff_addrs",
        {
            xff_addrs = "192.168.1.1, 216.160.83.56",
            xff_addrs_city = "Milton",
            xff_addrs_country = "US",
            xff_addrs_isp = "Century Link"
        }
    },
}
for i,v in ipairs(tests_last) do
    gh.add_geoip_xff(v[1], v[2])
    test.verify_msg_fields(v[3], v[1].Fields, i, true)
end

cfg.maxminddb_heka.xff = "all"
local tests_all = {
    {{Fields = {xff_addrs = "216.160.83.56, 192.168.1.1"}},
        "xff_addrs",
        {
            xff_addrs = "216.160.83.56, 192.168.1.1",
            xff_addrs_city = {"Milton", ""},
            xff_addrs_country = {"US", ""},
            xff_addrs_isp = {"Century Link", ""}
        }
    },
}

for i,v in ipairs(tests_all) do
    gh.add_geoip_xff(v[1], v[2])
    test.verify_msg_fields(v[3], v[1].Fields, i, true)
end


cfg.maxminddb_heka.xff = "first"
local tests_first = {
    {{Fields = {xff_addrs = "216.160.83.56, 192.168.1.1"}},
        "xff_addrs",
        {
            xff_addrs = "216.160.83.56, 192.168.1.1",
            xff_addrs_city = "Milton",
            xff_addrs_country = "US",
            xff_addrs_isp = "Century Link"
        }
    },
}
for i,v in ipairs(tests_first) do
    gh.add_geoip_xff(v[1], v[2])
    test.verify_msg_fields(v[3], v[1].Fields, i, true)
end


local t = cfg.maxminddb_heka.databases["GeoIP2-City-Test.mmdb"]
t._country = nil
cfg.maxminddb_heka.remove_original_field = true
local msg = {Fields = {remote_addr = "216.160.83.56"}}
gh.add_geoip(msg, "remote_addr")
test.verify_msg_fields({remote_addr_city = "Milton", remote_addr_isp = "Century Link"}, msg.Fields, 98, true)
cfg.maxminddb_heka.remove_original_field = false

t[""] = t._city -- replace the original field with city
t._city = nil
local msg = {Fields = {remote_addr = "216.160.83.56"}}
gh.add_geoip(msg, "remote_addr")
test.verify_msg_fields({remote_addr = "Milton", remote_addr_isp = "Century Link"}, msg.Fields, 99, true)
