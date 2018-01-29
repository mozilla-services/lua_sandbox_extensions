-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# pfsense Filter Log Format Parser (2.2)

## Variables

* `syslog_grammar` - Syslog Filter log format 2.2 grammar

--]]

local l = require "lpeg"
l.locale(l)
local ip = require "lpeg.ip_address"

local tonumber = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function text(name)
    return l.Cg((l.P(1) - ",")^0, name)
end

local function integer(name)
    return l.Cg(l.Ct(l.Cg(l.digit^1 / tonumber, "value") * l.Cg(l.Cc(2), "value_type")), name)
end

local function hex2integer(s)
    return {value = tonumber(s, 16), value_type = 2}
end

local rule_number                   = integer("rule_number")
local sub_rule_number               = integer("sub_rule_number")^-1
local anchor                        = text("anchor")
local tracker                       = integer("tracker")
local real_interface                = text("real_interface")
local reason                        = text("reason")
local action                        = l.Cg(l.P"pass" + "block", "action")
local direction                     = l.Cg(l.P"in" + "out", "direction")
local ip_version                    = l.Cg(l.P"4" + "6", "ip_version")

local tos                           = l.Cg((l.P"0x" * l.xdigit^1)^0 / hex2integer, "tos")
local ecn                           = text("ecn")
local ttl                           = integer("ttl")
local id                            = integer("id")
local offset                        = integer("offset")
local flags                         = text("flags")
local protocol_id                   = integer("protocol_id")
local protocol_text                 = text("protocol_text")
local ip4                           = tos * "," * ecn * "," * ttl * "," * id * "," * offset * "," * flags * "," * protocol_id * "," * protocol_text

local class                         = l.Cg((l.P"0x" * l.xdigit^1), "class")
local flow_label                    = text("flow_label")
local hop_limit                     = integer("hop_limit")
local ip6                           = class * "," * flow_label * "," * hop_limit * "," * protocol_text * "," * protocol_id

local length                        = integer("length")
local source_address                = l.Cg(ip.v4 + ip.v6, "source_address")
local destination_address           = l.Cg(ip.v4 + ip.v6, "destination_address")
local ip_data                       = length * "," * source_address * "," * destination_address

local source_port                   = integer("source_port")
local destination_port              = integer("destination_port")
local data_length                   = integer("data_length")
local tcp_flags                     = l.Cg(l.S"SA.FRPUEW", "tcp_flags")
local sequence_number               = integer("sequence_number")
local ack_number                    = integer("ack_number")
local tcp_window                    = integer("tcp_window")
local tcp_options                   = text("tcp_options")
local tcp_data                      = source_port * "," * destination_port * "," * data_length * "," * tcp_flags * "," * sequence_number * "," * ack_number * "," * tcp_window * "," * tcp_options

local udp_data                      = source_port * "," * destination_port * "," * data_length

local icmp_type                     = text("icmp_type")
local echo_data                     = integer("echo_id") * "," * integer("echo_sequence")
local icmp_destination_ip_address   = l.Cg(ip.v4 + ip.v6, "icmp_destination_ip_address")
local unreachproto_data             = icmp_destination_ip_address * "," * integer("unreachable_protocol_id") * ("," * integer("unreachable_port_number"))^-1
local other_unreachable_data        = text("icmp_description")
local needfrag_data                 = icmp_destination_ip_address * "," * integer("icmp_mtu")
local tstamp_data                   = integer("icmp_id") * "," * integer("icmp_sequence") * ("," * integer("icmp_otime") * "," * integer("icmp_rtime") * "," * integer("icmp_ttime"))^-1
local icmp_data                     = icmp_type * "," * (echo_data + unreachproto_data + other_unreachable_data + needfrag_data + tstamp_data  + text("icmp_description"))

local carp_data                     = text("carp_type") * "," * integer("carp_ttl") * "," * integer("vhid") * "," * integer("version") * "," * integer("advbase") * "," * integer("advskew")

local protocol_specific_data        = tcp_data + udp_data + icmp_data + carp_data
local ip_specific_data              = (ip4 + ip6) * "," * ip_data * (l.P"," * protocol_specific_data)^-1

syslog_grammar = l.Ct(rule_number * "," * sub_rule_number * "," * anchor * "," * tracker * "," * real_interface * "," * reason * "," * action * "," * direction * "," * ip_version * (l.P"," * ip_specific_data)^-1)

return M

