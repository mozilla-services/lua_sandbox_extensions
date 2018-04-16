-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local ipu = require "iputils"
local string = require "string"

local cidrs_a = { "10.0.0.0/16", "192.168.1.0/24", "127.0.0.1/32" }
local cidrs_b = { "10.0.0.10", "192.168.20.20" }
local cidrs_c = { "0.0.0.0/0" }
local cidrs_invalid_a = { "10.0.0.0/16", "192.168.1.0/24", "300.300.300.1" }
local cidrs_invalid_b = { "10.0.0.0/16", "" }
local cidrs_invalid_c = { "192.168.1.0/24", 0 }

local function chk_ip_in_cidr(want, ip, bincidrs)
    f, err = ipu.ip_in_cidrs(ip, bincidrs)
    if f == want then return end

    error(string.format("test: chk_ip_in_cidr: %s, wanted %s got %s", tostring(ip), tostring(want), tostring(f)))
end

-- Test invalid CIDR lists
local pc = ipu.parse_cidrs(cidrs_invalid_a)
assert(not pc, "test: iputils.parse_cidrs did not return nil")
pc = ipu.parse_cidrs(cidrs_invalid_b)
assert(not pc, "test: iputils.parse_cidrs did not return nil")
pc = ipu.parse_cidrs(cidrs_invalid_c)
assert(not pc, "test: iputils.parse_cidrs did not return nil")

-- Test CIDR list with a 32 bit mask
pc = ipu.parse_cidrs(cidrs_b)
assert(pc, "test: iputils.parse_cidrs returned nil")

chk_ip_in_cidr(true, "10.0.0.10", pc)
chk_ip_in_cidr(true, "192.168.20.20", pc)
chk_ip_in_cidr(false, "192.168.20.21", pc)

-- Test match all
pc = ipu.parse_cidrs(cidrs_c)
chk_ip_in_cidr(true, "127.0.0.1", pc)

-- Test standard expected case
pc = ipu.parse_cidrs(cidrs_a)
assert(pc, "test: iputils.parse_cidrs returned nil")

chk_ip_in_cidr(true, "10.0.0.1", pc)
chk_ip_in_cidr(true, "10.0.254.254", pc)
chk_ip_in_cidr(false, "10.2.0.0", pc)
chk_ip_in_cidr(false, "172.16.25.25", pc)
chk_ip_in_cidr(nil, "1.2", pc)
chk_ip_in_cidr(nil, "invalid", pc)
chk_ip_in_cidr(nil, nil, pc)
chk_ip_in_cidr(nil, nil, nil)
chk_ip_in_cidr(nil, "999.999.999.999", pc)
