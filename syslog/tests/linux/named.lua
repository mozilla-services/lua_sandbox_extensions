-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.named".syslog_grammar
local log
local fields

log = "lame server resolving '40.30.20.10.in-addr.arpa' (in '30.20.10.in-addr.arpa'?): 10.11.12.13#53"
fields = grammar:match(log)
assert(fields.dns_error == 'lame server', fields.dns_error)
assert(fields.dns_name == '40.30.20.10.in-addr.arpa', fields.dns_name)
assert(fields.dns_domain == '30.20.10.in-addr.arpa', fields.dns_domain)
assert(fields.dns_addr.value == '10.11.12.13', fields.dns_addr.value)
assert(fields.dns_addr.representation == 'ipv4', fields.dns_addr.representation)
assert(fields.dns_port == 53, fields.dns_port)

log = "host unreachable resolving 'ipv6.example.org/AAAA/IN': 2001:503:231d::2:30#53"
fields = grammar:match(log)
assert(fields.dns_error == 'host unreachable', fields.dns_error)
assert(fields.dns_name == 'ipv6.example.org', fields.dns_name)
assert(fields.dns_type == 'AAAA', fields.dns_type)
assert(fields.dns_class == 'IN', fields.dns_class)
assert(fields.dns_addr.value == '2001:503:231d::2:30', fields.dns_addr.value)
assert(fields.dns_addr.representation == 'ipv6', fields.dns_addr.representation)
assert(fields.dns_port == 53, fields.dns_port)

log = "DNS format error from 134.170.107.24#53 resolving cid-ff58b408a75804a8.users.storage.live.com/AAAA for client 10.2.3.4#60466: Name storage.live.com (SOA) not subdomain of zone users.storage.live.com -- invalid response"
fields = grammar:match(log)
assert(fields.dns_error == 'DNS format error', fields.dns_error)
assert(fields.dns_addr.value == '134.170.107.24', fields.dns_addr.value)
assert(fields.dns_addr.representation == 'ipv4', fields.dns_addr.representation)
assert(fields.dns_port == 53, fields.dns_port)
assert(fields.dns_name == 'cid-ff58b408a75804a8.users.storage.live.com', fields.dns_name)
assert(fields.dns_type == 'AAAA', fields.dns_type)
assert(fields.dns_client_addr.value == '10.2.3.4', fields.dns_client_addr.value)
assert(fields.dns_client_addr.representation == 'ipv4', fields.dns_client_addr.representation)
assert(fields.dns_client_port == 60466, fields.dns_client_port)
assert(fields.dns_message == "Name storage.live.com (SOA) not subdomain of zone users.storage.live.com -- invalid response", fields.dns_message)

log = 'DNS format error from 184.105.66.196#53 resolving ns-os1.qq.com/AAAA: Name qq.com (SOA) not subdomain of zone ns-os1.qq.com -- invalid response'
fields = grammar:match(log)
assert(fields.dns_error == 'DNS format error', fields.dns_error)
assert(fields.dns_addr.value == '184.105.66.196', fields.dns_addr.value)
assert(fields.dns_addr.representation == 'ipv4', fields.dns_addr.representation)
assert(fields.dns_port == 53, fields.dns_port)
assert(fields.dns_name == 'ns-os1.qq.com', fields.dns_name)
assert(fields.dns_type == 'AAAA', fields.dns_type)
assert(fields.dns_message == "Name qq.com (SOA) not subdomain of zone ns-os1.qq.com -- invalid response", fields.dns_message)

log = "client 10.8.6.1#17069/key trusty (pc.example.org): view internal: transfer of 'pc.example.org/IN': IXFR started: TSIG trusty (serial 12 -> 14)"
fields = grammar:match(log)
assert(fields.dns_client_addr.value == '10.8.6.1', fields.dns_client_addr.value)
assert(fields.dns_client_addr.representation == 'ipv4', fields.dns_client_addr.representation)
assert(fields.dns_client_port == 17069, fields.dns_client_port)
assert(fields.dns_client_signer == 'trusty', fields.dns_client_signer)
assert(fields.dns_name == 'pc.example.org', fields.dns_name)
--assert(fields.dns_view == 'internal', fields.dns_view)
assert(fields.dns_message == "transfer of 'pc.example.org/IN': IXFR started: TSIG trusty (serial 12 -> 14)", fields.dns_message)

log = "success resolving 'ns1.example.com/AAAA' (in 'example.com'?) after disabling EDNS"
fields = grammar:match(log)
assert(fields.dns_name == 'ns1.example.com', fields.dns_name)
assert(fields.dns_type == 'AAAA', fields.dns_type)
assert(fields.dns_domain == 'example.com', fields.dns_domain)
assert(fields.dns_message == "disabling EDNS", fields.dns_message)

log = "zone 12.11.10.in-addr.arpa/IN/internal: sending notifies (serial 42)"
fields = grammar:match(log)
assert(fields.dns_domain == '12.11.10.in-addr.arpa', fields.dns_domain)
assert(fields.dns_class == 'IN', fields.dns_class)
assert(fields.dns_view == 'internal', fields.dns_view)
assert(fields.dns_message == "sending notifies", fields.dns_message)
assert(fields.dns_serial == 42, fields.dns_serial)

log = "clients-per-query decreased to 22"
fields = grammar:match(log)
assert(fields.dns_clients_per_query == 22, fields.dns_clients_per_query)
