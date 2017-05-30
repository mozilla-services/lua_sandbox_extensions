-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux dhcpclient Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"
local ip = require "lpeg.ip_address"

local tonumber = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

syslog_grammar = l.Ct(
    (
        -- "DHCPDISCOVER on %s to %s port %d interval %ld"
        l.Cg(l.P"DHCPDISCOVER", "dhcp_type")
        * l.P" on "
        * sl.capture_followed_by("dhcp_client_interface", " to ")
        * l.Cg(ip.v4_field, "dhcp_server_addr")
        * l.P" port "
        * l.Cg(l.digit^1 / tonumber, "dhcp_server_port")
        * l.P" interval "
        * l.Cg(l.digit^1 / tonumber, "dhcp_client_interval_seconds")
        * l.P(-1)
        )
    + (
        -- "DHCPREQUEST on %s to %s port %d"
        -- "DHCPDECLINE on %s to %s port %d"
        -- "DHCPRELEASE on %s to %s port %d"
        l.Cg(l.P"DHCPREQUEST" + l.P"DHCPDECLINE" + l.P"DHCPRELEASE", "dhcp_type")
        * l.P" on "
        * sl.capture_followed_by("dhcp_client_interface", " to ")
        * l.Cg(ip.v4_field, "dhcp_server_addr")
        * l.P" port "
        * l.Cg(l.digit^1 / tonumber, "dhcp_server_port")
        * l.P(-1)
    )
    + (
        -- "DHCPACK from %s"
        l.Cg(l.P"DHCPACK", "dhcp_type")
        * l.P" from "
        * l.Cg(ip.v4_field, "dhcp_server_addr")
        * l.P(-1)
        )
    + (
        -- "bound to %s -- renewal in %ld seconds."
        l.P"bound to "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" -- renewal in "
        * l.Cg(l.digit^1 / tonumber, "dhcp_client_renewal_seconds")
        * l.P" seconds."
        * l.P(-1)
        )
    )

return M
