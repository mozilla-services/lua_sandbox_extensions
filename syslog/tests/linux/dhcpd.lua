-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.dhcpd".syslog_grammar
local log
local fields

log = 'DHCPINFORM from 192.168.0.45 via 192.168.0.1'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPINFORM', fields.dhcp_type)
assert(fields.dhcp_client_addr.value == '192.168.0.45', fields.dhcp_client_addr)
assert(fields.dhcp_client_addr.representation == 'ipv4', fields.dhcp_client_addr)
assert(fields.dhcp_source == '192.168.0.1', fields.dhcp_source)

log = 'DHCPDISCOVER from aa:bb:cc:dd:ee:ff via 10.2.3.4: unknown network segment'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPDISCOVER', fields.dhcp_type)
assert(fields.dhcp_client_hw_addr == 'aa:bb:cc:dd:ee:ff', fields.dhcp_client_hw_addr)
assert(fields.dhcp_source == '10.2.3.4', fields.dhcp_source)
assert(fields.dhcp_message == 'unknown network segment', fields.dhcp_message)

log = 'DHCPACK to 192.168.2.3 (aa:bb:cc:dd:ee:ff) via vlan42'
fields = grammar:match(log)
assert(fields.dhcp_type == 'DHCPACK', fields.dhcp_type)
assert(fields.dhcp_client_hw_addr == 'aa:bb:cc:dd:ee:ff', fields.dhcp_client_hw_addr)
assert(fields.dhcp_source == 'vlan42', fields.dhcp_source)
