-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux dhcpd Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"
local ip = require "lpeg.ip_address"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local dhcpd_hw_addr = l.xdigit * l.xdigit * (l.S":" * l.xdigit * l.xdigit)^0

syslog_grammar = l.Ct(
    (
        l.Cg(l.P"BOOTREQUEST", "dhcp_type")
        * l.P" from "
        * l.Cg(dhcpd_hw_addr, "dhcp_client_hw_addr")
        * l.P" via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * l.P(-1)
        )
    + (
        l.Cg(l.P"BOOTREPLY", "dhcp_type")
        * l.P" for "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" to "
        * sl.capture_followed_by("dhcp_client_addr", " (")
        * l.Cg(dhcpd_hw_addr, "dhcp_client_hw_addr")
        * l.P") via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * l.P(-1)
        ) 
    + (
        l.Cg(l.P"DHCPDISCOVER", "dhcp_type")
        * l.P" from "
        * l.Cg(dhcpd_hw_addr + l.P"<no identifier>", "dhcp_client_hw_addr")
        * l.P" "
        * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
        * l.P"via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
        * l.P(-1)
        )
    + (
        l.Cg(l.P"DHCPOFFER" + l.P"DHCPACK" + l.P"BOOTREPLY", "dhcp_type")
         * l.P" on "
         * l.Cg(ip.v4_field, "dhcp_client_addr")
         * l.P" to "
         * l.Cg((l.P(1)-l.P" ")^1, "dhcp_client_hw_addr")
         * l.P" "
         * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
         * l.P"via "
         * l.Cg((l.P(1)-l.P" ")^1, "dhcp_source")
         * (l.P" [" * l.Cg(sl.integer, "dhcp_lease_time") * l.P"]")^-1
         * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
         * l.P(-1)
        )
    + (
        l.Cg(l.P"DHCPACK", "dhcp_type")
        * l.P" to "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" ("
        * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hw_addr")
        * l.P") via "
        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_source")
        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
        * ( l.P" [" * l.Cg(sl.integer, "dhcp_lease_time") * l.P"]")^-1
        * l.P(-1)
        ) 
    + (
        l.Cg(l.P"DHCPNAK", "dhcp_type")
        * l.P" on "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" to "
        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_client_hw_addr")
        * l.P" via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * l.P(-1)
        )
    + (
        l.Cg(l.P"DHCPREQUEST", "dhcp_type")
        * l.P" for "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * (l.P" (" * l.Cg((l.P(1)-l.P")")^1, "dhcp_server_addr") * l.P")")^-1
        * l.P" from "
        * l.Cg(dhcpd_hw_addr + l.P"<no identifier>", "dhcp_client_hw_addr")
        * l.P" "
        * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
        * l.P"via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
        * l.P(-1)
        )
    + (
        l.Cg(l.P"DHCPINFORM", "dhcp_type")
        * l.P" from "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" via "
        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
        * l.P(-1)
        )
    + (
        l.Cg(l.P"balancing", "dhcp_pool_result")
        * l.P" pool"
        * sl.capture_followed_by("dhcp_pool_id", " ")
        * sl.capture_followed_by("dhcp_network", "  total ")
        * l.Cg(sl.integer, "dhcp_lease_count")
        * l.P"  free "
        * l.Cg(sl.integer, "dhcp_free_leases")
        * l.P"  backup "
        * l.Cg(sl.integer, "dhcp_backup_leases")
        * l.P"  lts "
        * l.Cg(sl.integer, "dhcp_lts")
        * l.P"  max-own (+/-)"
        * l.Cg(sl.integer, "dhcp_hold")
        * (l.P"  (requesting peer rebalance!)")^-1
        * l.P(-1)
        )
    + (
        l.Cg(l.P"balanced" + l.P"IMBALANCED", "dhcp_pool_result")
        * l.P" pool"
        * sl.capture_followed_by("dhcp_network", "  total ")
        * l.Cg(sl.integer, "dhcp_lease_count")
        * l.P"  free "
        * l.Cg(sl.integer, "dhcp_free_leases")
        * l.P"  backup "
        * l.Cg(sl.integer, "dhcp_backup_leases")
        * l.P"  lts "
        * l.Cg(sl.integer, "dhcp_lts")
        * l.P"  max-misbal "
        * l.Cg(sl.integer, "dhcp_thresh")
        * l.P(-1)
        )
    + (
        l.P"bind update on "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" from "
        * sl.capture_followed_by("dhcp_failover_peer", " ")
        * l.Cg(l.P"rejected", "dhcp_bind_update_status")
        * l.P": "
        * l.Cg(l.P(1)^1, "dhcp_message")
        )
    + (
        l.P"bind update on "
        * l.Cg(ip.v4_field, "dhcp_client_addr")
        * l.P" "
        * l.Cg(l.P"got ack", "dhcp_bind_update_status")
        * l.P" from "
        * sl.capture_followed_by("dhcp_failover_peer", ": ")
        * l.Cg(l.P(1)^1, "dhcp_message")
        )
    )

return M
