-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.dhclient".syslog_grammar
local log
local fields

log = 'DHCPDISCOVER on eth0 to 10.20.30.42 port 67 interval 18000'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPDISCOVER', fields.dhcp_type)
assert(fields.dhcp_client_interface == 'eth0', fields.dhcdhcp_client_interfacep_source)
assert(fields.dhcp_server_addr.value == '10.20.30.42', fields.dhcp_server_addr)
assert(fields.dhcp_server_addr.representation == 'ipv4', fields.dhcp_server_addr)
assert(fields.dhcp_server_port == 67, fields.dhcp_server_port)
assert(fields.dhcp_client_interval_seconds == 18000, fields.dhcp_client_interval_seconds)

log = 'DHCPREQUEST on eth0 to 10.20.30.42 port 67'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPREQUEST', fields.dhcp_type)
assert(fields.dhcp_client_interface == 'eth0', fields.dhcdhcp_client_interfacep_source)
assert(fields.dhcp_server_addr.value == '10.20.30.42', fields.dhcp_server_addr)
assert(fields.dhcp_server_addr.representation == 'ipv4', fields.dhcp_server_addr)
assert(fields.dhcp_server_port == 67, fields.dhcp_server_port)

log = 'DHCPACK from 10.20.30.42'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPACK', fields.dhcp_type)
assert(fields.dhcp_server_addr.value == '10.20.30.42', fields.dhcp_server_addr)
assert(fields.dhcp_server_addr.representation == 'ipv4', fields.dhcp_server_addr)

log = 'bound to 10.20.30.40 -- renewal in 20346 seconds.'
fields = grammar:match(log)
assert(fields.dhcp_client_addr.value == '10.20.30.40', fields.dhcp_client_addr)
assert(fields.dhcp_client_addr.representation == 'ipv4', fields.dhcp_client_addr)
assert(fields.dhcp_client_renewal_seconds == 20346, fields.dhcp_client_renewal_seconds)
