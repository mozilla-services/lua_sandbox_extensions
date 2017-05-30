-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux kernel Grammar Module

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

-- cf. (linux.git)/net/ipv4/netfilter/nf_log_ipv4.c
-- cf. (linux.git)/net/ipv6/netfilter/nf_log_ipv6.c
-- cf. (linux.git)/net/netfilter/nf_log_common.c
local function netfilter_flag(flag, name)
    return (l.P(flag) * l.Cg(l.Cc(true), name))^-1
end

local netfilter_tcp = l.P"PROTO="
                    * l.Cg(l.P"TCP", "nf_protocol")
                    * l.P" SPT="
                    * l.Cg(sl.integer, "nf_spt")
                    * l.P" DPT="
                    * l.Cg(sl.integer, "nf_dpt")* (
                        l.P" SEQ="
                      * l.Cg(sl.integer, "nf_seq")
                      * l.P" ACK="
                      * l.Cg(sl.integer, "nf_ack")
                      )^-1
                    * l.P" WINDOW="
                    * l.Cg(sl.integer, "nf_window")
                    * l.P" RES="
                    * l.Cg(sl.notspace, "nf_res")
                    * l.P" "
                    * netfilter_flag("CWR ", "nf_tcp_cwr")
                    * netfilter_flag("ECE ", "nf_tcp_ece")
                    * netfilter_flag("URG ", "nf_tcp_urg")
                    * netfilter_flag("ACK ", "nf_tcp_ack")
                    * netfilter_flag("PSH ", "nf_tcp_psh")
                    * netfilter_flag("RST ", "nf_tcp_rst")
                    * netfilter_flag("SYN ", "nf_tcp_syn")
                    * netfilter_flag("FIN ", "nf_tcp_fin")
                    * l.P"URGP="
                    * l.Cg(sl.integer, "nf_urgp")
                    * l.P" "

local netfilter_udp = l.P"PROTO="
                    * l.Cg(l.P"UDP", "nf_protocol")
                    * l.P" SPT="
                    * l.Cg(sl.integer, "nf_spt")
                    * l.P" DPT="
                    * l.Cg(sl.integer, "nf_dpt")
                    * l.P" LEN="
                    * l.Cg(sl.integer, "nf_udp_len")
                    * l.P" "

local netfilter_icmp = l.P"PROTO="
                     * l.Cg(l.P"ICMP", "nf_protocol")
                     * l.P" TYPE="
                     * l.Cg(sl.integer, "nf_icmp_type")
                     * l.P" CODE="
                     * l.Cg(sl.integer, "nf_icmp_code")
                     * ( -- echoreply or echo
                         l.P" ID="
                       * l.Cg(sl.integer, "nf_icmp_id")
                       * l.P" SEQ="
                       * l.Cg(sl.integer, "nf_icmp_seq")
                       )^-1
                     * ( -- parameterprob
                         l.P" PARAMETER="
                       * l.Cg(sl.integer, "nf_icmp_parameter")
                       )^-1
                     * ( -- redirect
                         l.P" GATEWAY="
                       * l.Cg(ip.v4_field, "nf_icmp_gateway")
                       )^-1
                     * l.P" "

local netfilter_icmpv6 = l.P"PROTO="
                       * l.Cg(l.P"ICMPv6", "nf_protocol")
                       * l.P" TYPE="
                       * l.Cg(sl.integer, "nf_icmpv6_type")
                       * l.P" CODE="
                       * l.Cg(sl.integer, "nf_icmpv6_code")
                       * ( -- echoreply or echo
                           l.P" ID="
                         * l.Cg(sl.integer, "nf_icmpv6_id")
                         * l.P" SEQ="
                         * l.Cg(sl.integer, "nf_icmpv6_seq")
                         )^-1
                       * ( -- paramprob
                           l.P" POINTER="
                         * l.Cg(sl.integer, "nf_icmpv6_pointer")
                         )^-1
                       * ( -- time exceed
                           l.P" MTU="
                         * l.Cg(sl.integer, "nf_icmpv6_mtu")
                         )^-1
                       * l.P" "

local netfilter_other = l.P"PROTO=" * l.Cg(sl.notspace, "nf_protocol")

local netfilter_ipv4 = l.P" SRC="
                     * l.Cg(ip.v4_field, "nf_src_ip")
                     * l.P" DST="
                     * l.Cg(ip.v4_field, "nf_dst_ip")
                     * l.P" LEN="
                     * l.Cg(sl.integer, "nf_len")
                     * l.P" TOS="
                     * l.Cg(sl.notspace, "nf_tos")
                     * l.P" PREC="
                     * l.Cg(sl.notspace, "nf_prec")
                     * l.P" TTL="
                     * l.Cg(sl.integer, "nf_ttl")
                     * l.P" ID="
                     * l.Cg(sl.integer, "nf_id")
                     * l.P" "
                     * netfilter_flag("CE ", "nf_ce")
                     * netfilter_flag("DF ", "nf_df")
                     * netfilter_flag("MF ", "nf_mf")
                     * (l.P"FRAG:" * l.Cg(sl.integer, "nf_frag") * l.P" ")^-1
                     * (
                         netfilter_tcp
                       + netfilter_udp
                       + netfilter_icmp
                       + netfilter_other
                       )

local netfilter_ipv6 = l.P" SRC="
                     * l.Cg(ip.v6_field, "nf_src_ip")
                     * l.P" DST="
                     * l.Cg(ip.v6_field, "nf_dst_ip")
                     * l.P" LEN="
                     * l.Cg(sl.integer, "nf_len")
                     * l.P" TC="
                     * l.Cg(sl.integer, "nf_tc")
                     * l.P" HOPLIMIT="
                     * l.Cg(sl.integer, "nf_hoplimit")
                     * l.P" FLOWLBL="
                     * l.Cg(sl.integer, "nf_flowlbl")
                     * l.P" "
                     * (
                         netfilter_tcp
                       + netfilter_udp
                       + netfilter_icmpv6
                       + netfilter_other
                       )

syslog_grammar = l.Ct(
    (
        l.P"[" * l.Cg(sl.float, "monotonic_timestamp") * l.P"] "
        * sl.capture_until("nf_prefix", "IN=")
        * l.P"IN="
        * l.Cg(sl.notspace, "nf_in_interface")
        * l.P" OUT="
        * l.Cg(sl.notspace, "nf_out_interface")
        * (
            l.P" MAC=" 
            * l.Cg(sl.commonmac, "nf_dst_mac")
            * l.P":" 
            * l.Cg(sl.commonmac, "nf_src_mac")
            )^-1
        * (netfilter_ipv4 + netfilter_ipv6)
        * (
            l.P"UID="
            * l.Cg(sl.integer, "nf_uid")
            * l.P" GID="
            * l.Cg(sl.integer, "nf_gid")
            * l.P" "
            )^-1
        * (
            l.P"MARK="
            * l.Cg(sl.notspace, "nf_mark")
            * l.P" "
            )^-1
        )
    )

return M
