-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Syslog Message Module


## Functions

### get_prog_grammar

Retrieves the parser for a particular program.

*Arguments*
- prog (string) - program name e.g. "CRON", "dhclient", "dhcpd"...

*Return*
- grammar (LPEG user data object) or nil if the `programname` isn't found

### get_wildcard_grammar

*Arguments*
- prog (string) - program name, currently only accepts "PAM"

*Return*
- grammar (LPEG user data object) or nil if the `programname` isn't found
--]]


local string = require "string"
local ip = require "lpeg.ip_address"
local l = require "lpeg"
l.locale(l)
local tonumber = tonumber
local type = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local prog_grammar = {}
local wildcard_grammar = {}

-- LPEG helpers
local integer = (l.P"-"^-1 * l.digit^1) / tonumber
local float = (l.P"-"^-1 * l.digit^1 * (l.P"." * l.digit^1)^1) / tonumber
local notspace = (l.P(1)-l.P" ")^0
local commonmac = l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
                * l.P":" * l.xdigit * l.xdigit
local ipv4    = l.Ct(l.Cg(ip.v4, "value") * l.Cg(l.Cc"ipv4", "representation"))
local ipv6    = l.Ct(l.Cg(ip.v6, "value") * l.Cg(l.Cc"ipv6", "representation"))
local ipv46   = ipv4 + ipv6

local function capture_until(var, txt)
    return l.Cg((l.P(1) - l.P(txt))^0, var)
end
local function capture_followed_by(var, txt)
    return capture_until(var, txt) * l.P(txt)
end

-- programname=CRON
prog_grammar["CRON"] = l.Ct(
                       l.P"("
                     * capture_followed_by("cron_username", ") ")
                     * capture_followed_by("cron_event", " (")
                     * capture_followed_by("cron_detail", ")")
                     * l.P(-1)
                     )

-- programname=crontab
prog_grammar["crontab"] = prog_grammar["CRON"]

-- programname=dhclient
prog_grammar["dhclient"] = l.Ct(
                         ( -- "DHCPDISCOVER on %s to %s port %d interval %ld"
                             l.Cg(l.P"DHCPDISCOVER", "dhcp_type")
                           * l.P" on "
                           * capture_followed_by("dhcp_client_interface", " to ")
                           * l.Cg(ipv4, "dhcp_server_addr")
                           * l.P" port "
                           * l.Cg(l.digit^1 / tonumber, "dhcp_server_port")
                           * l.P" interval "
                           * l.Cg(l.digit^1 / tonumber, "dhcp_client_interval_seconds")
                           * l.P(-1)
                         ) + ( -- "DHCPREQUEST on %s to %s port %d"
                               -- "DHCPDECLINE on %s to %s port %d"
                               -- "DHCPRELEASE on %s to %s port %d"
                             l.Cg(l.P"DHCPREQUEST" + l.P"DHCPDECLINE" + l.P"DHCPRELEASE", "dhcp_type")
                           * l.P" on "
                           * capture_followed_by("dhcp_client_interface", " to ")
                           * l.Cg(ipv4, "dhcp_server_addr")
                           * l.P" port "
                           * l.Cg(l.digit^1 / tonumber, "dhcp_server_port")
                           * l.P(-1)
                         ) + ( -- "DHCPACK from %s"
                             l.Cg(l.P"DHCPACK", "dhcp_type")
                           * l.P" from "
                           * l.Cg(ipv4, "dhcp_server_addr")
                           * l.P(-1)
                         ) + ( -- "bound to %s -- renewal in %ld seconds."
                             l.P"bound to "
                           * l.Cg(ipv4, "dhcp_client_addr")
                           * l.P" -- renewal in "
                           * l.Cg(l.digit^1 / tonumber, "dhcp_client_renewal_seconds")
                           * l.P" seconds."
                           * l.P(-1)
                         ))

-- programname=dhcpd
local dhcpd_hw_addr = l.xdigit * l.xdigit * (l.S":" * l.xdigit * l.xdigit)^0
prog_grammar["dhcpd"] = l.Ct(
                      (
                          l.Cg(l.P"BOOTREQUEST", "dhcp_type")
                        * l.P" from "
                        * l.Cg(dhcpd_hw_addr, "dhcp_client_hw_addr")
                        * l.P" via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"BOOTREPLY", "dhcp_type")
                        * l.P" for "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" to "
                        * capture_followed_by("dhcp_client_addr", " (")
                        * l.Cg(dhcpd_hw_addr, "dhcp_client_hw_addr")
                        * l.P") via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPDISCOVER", "dhcp_type")
                        * l.P" from "
                        * l.Cg(dhcpd_hw_addr + l.P"<no identifier>", "dhcp_client_hw_addr")
                        * l.P" "
                        * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
                        * l.P"via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPOFFER" + l.P"DHCPACK" + l.P"BOOTREPLY", "dhcp_type")
                        * l.P" on "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" to "
                        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_client_hw_addr")
                        * l.P" "
                        * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
                        * l.P"via "
                        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_source")
                        * ( l.P" ["
                          * l.Cg(integer, "dhcp_lease_time")
                          * l.P"]")^-1
                        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPACK", "dhcp_type")
                        * l.P" to "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" ("
                        * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hw_addr")
                        * l.P") via "
                        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_source")
                        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
                        * ( l.P" ["
                          * l.Cg(integer, "dhcp_lease_time")
                          * l.P"]")^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPNAK", "dhcp_type")
                        * l.P" on "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" to "
                        * l.Cg((l.P(1)-l.P" ")^1, "dhcp_client_hw_addr")
                        * l.P" via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPREQUEST", "dhcp_type")
                        * l.P" for "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * (l.P" (" * l.Cg((l.P(1)-l.P")")^1, "dhcp_server_addr") * l.P")")^-1
                        * l.P" from "
                        * l.Cg(dhcpd_hw_addr + l.P"<no identifier>", "dhcp_client_hw_addr")
                        * l.P" "
                        * (l.P"(" * l.Cg((l.P(1)-l.P")")^1, "dhcp_client_hostname") * l.P") ")^-1
                        * l.P"via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"DHCPINFORM", "dhcp_type")
                        * l.P" from "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" via "
                        * l.Cg((l.P(1)-l.P":")^1, "dhcp_source")
                        * (l.P": " * l.Cg(l.P(1)^1, "dhcp_message"))^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"balancing", "dhcp_pool_result")
                        * l.P" pool"
                        * capture_followed_by("dhcp_pool_id", " ")
                        * capture_followed_by("dhcp_network", "  total ")
                        * l.Cg(integer, "dhcp_lease_count")
                        * l.P"  free "
                        * l.Cg(integer, "dhcp_free_leases")
                        * l.P"  backup "
                        * l.Cg(integer, "dhcp_backup_leases")
                        * l.P"  lts "
                        * l.Cg(integer, "dhcp_lts")
                        * l.P"  max-own (+/-)"
                        * l.Cg(integer, "dhcp_hold")
                        * (l.P"  (requesting peer rebalance!)")^-1
                        * l.P(-1)
                      ) + (
                          l.Cg(l.P"balanced" + l.P"IMBALANCED", "dhcp_pool_result")
                        * l.P" pool"
                        * capture_followed_by("dhcp_network", "  total ")
                        * l.Cg(integer, "dhcp_lease_count")
                        * l.P"  free "
                        * l.Cg(integer, "dhcp_free_leases")
                        * l.P"  backup "
                        * l.Cg(integer, "dhcp_backup_leases")
                        * l.P"  lts "
                        * l.Cg(integer, "dhcp_lts")
                        * l.P"  max-misbal "
                        * l.Cg(integer, "dhcp_thresh")
                        * l.P(-1)
                      ) + (
                          l.P"bind update on "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" from "
                        * capture_followed_by("dhcp_failover_peer", " ")
                        * l.Cg(l.P"rejected", "dhcp_bind_update_status")
                        * l.P": "
                        * l.Cg(l.P(1)^1, "dhcp_message")
                      ) + (
                          l.P"bind update on "
                        * l.Cg(ipv4, "dhcp_client_addr")
                        * l.P" "
                        * l.Cg(l.P"got ack", "dhcp_bind_update_status")
                        * l.P" from "
                        * capture_followed_by("dhcp_failover_peer", ": ")
                        * l.Cg(l.P(1)^1, "dhcp_message")
                      ))

-- programname=groupadd
prog_grammar["groupadd"] = l.Ct(
                        (
                            l.P"new group: name="
                          * capture_followed_by("group_name", ", GID=")
                          * l.Cg(l.digit^1 / tonumber, "gid")
                          * l.P(-1)
                        ))

-- programname=groupdel
prog_grammar["groupdel"] = l.Ct(
                        (
                            l.P"group '"
                          * capture_followed_by("group_name", "' removed")
                          * (l.P" from " * l.Cg(l.P(1)^1, "group_dbname"))^-1
                        ))

-- programname=kernel
-- cf. (linux.git)/net/ipv4/netfilter/nf_log_ipv4.c
-- cf. (linux.git)/net/ipv6/netfilter/nf_log_ipv6.c
-- cf. (linux.git)/net/netfilter/nf_log_common.c
local function netfilter_flag(flag, name)
    return (l.P(flag) * l.Cg(l.Cc(true), name))^-1
end
local netfilter_tcp = l.P"PROTO="
                    * l.Cg(l.P"TCP", "nf_protocol")
                    * l.P" SPT="
                    * l.Cg(integer, "nf_spt")
                    * l.P" DPT="
                    * l.Cg(integer, "nf_dpt")
                    * (
                        l.P" SEQ="
                      * l.Cg(integer, "nf_seq")
                      * l.P" ACK="
                      * l.Cg(integer, "nf_ack")
                      )^-1
                    * l.P" WINDOW="
                    * l.Cg(integer, "nf_window")
                    * l.P" RES="
                    * l.Cg(notspace, "nf_res")
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
                    * l.Cg(integer, "nf_urgp")
                    * l.P" "
local netfilter_udp = l.P"PROTO="
                    * l.Cg(l.P"UDP", "nf_protocol")
                    * l.P" SPT="
                    * l.Cg(integer, "nf_spt")
                    * l.P" DPT="
                    * l.Cg(integer, "nf_dpt")
                    * l.P" LEN="
                    * l.Cg(integer, "nf_udp_len")
                    * l.P" "
local netfilter_icmp = l.P"PROTO="
                     * l.Cg(l.P"ICMP", "nf_protocol")
                     * l.P" TYPE="
                     * l.Cg(integer, "nf_icmp_type")
                     * l.P" CODE="
                     * l.Cg(integer, "nf_icmp_code")
                     * ( -- echoreply or echo
                         l.P" ID="
                       * l.Cg(integer, "nf_icmp_id")
                       * l.P" SEQ="
                       * l.Cg(integer, "nf_icmp_seq")
                       )^-1
                     * ( -- parameterprob
                         l.P" PARAMETER="
                       * l.Cg(integer, "nf_icmp_parameter")
                       )^-1
                     * ( -- redirect
                         l.P" GATEWAY="
                       * l.Cg(ipv4, "nf_icmp_gateway")
                       )^-1
                     * l.P" "
local netfilter_icmpv6 = l.P"PROTO="
                       * l.Cg(l.P"ICMPv6", "nf_protocol")
                       * l.P" TYPE="
                       * l.Cg(integer, "nf_icmpv6_type")
                       * l.P" CODE="
                       * l.Cg(integer, "nf_icmpv6_code")
                       * ( -- echoreply or echo
                           l.P" ID="
                         * l.Cg(integer, "nf_icmpv6_id")
                         * l.P" SEQ="
                         * l.Cg(integer, "nf_icmpv6_seq")
                         )^-1
                       * ( -- paramprob
                           l.P" POINTER="
                         * l.Cg(integer, "nf_icmpv6_pointer")
                         )^-1
                       * ( -- time exceed
                           l.P" MTU="
                         * l.Cg(integer, "nf_icmpv6_mtu")
                         )^-1
                       * l.P" "
local netfilter_other = l.P"PROTO="
                      * l.Cg(notspace, "nf_protocol")
local netfilter_ipv4 = l.P" SRC="
                     * l.Cg(ipv4, "nf_src_ip")
                     * l.P" DST="
                     * l.Cg(ipv4, "nf_dst_ip")
                     * l.P" LEN="
                     * l.Cg(integer, "nf_len")
                     * l.P" TOS="
                     * l.Cg(notspace, "nf_tos")
                     * l.P" PREC="
                     * l.Cg(notspace, "nf_prec")
                     * l.P" TTL="
                     * l.Cg(integer, "nf_ttl")
                     * l.P" ID="
                     * l.Cg(integer, "nf_id")
                     * l.P" "
                     * netfilter_flag("CE ", "nf_ce")
                     * netfilter_flag("DF ", "nf_df")
                     * netfilter_flag("MF ", "nf_mf")
                     * (l.P"FRAG:" * l.Cg(integer, "nf_frag") * l.P" ")^-1
                     * (
                         netfilter_tcp
                       + netfilter_udp
                       + netfilter_icmp
                       + netfilter_other
                       )
local netfilter_ipv6 = l.P" SRC="
                     * l.Cg(ipv6, "nf_src_ip")
                     * l.P" DST="
                     * l.Cg(ipv6, "nf_dst_ip")
                     * l.P" LEN="
                     * l.Cg(integer, "nf_len")
                     * l.P" TC="
                     * l.Cg(integer, "nf_tc")
                     * l.P" HOPLIMIT="
                     * l.Cg(integer, "nf_hoplimit")
                     * l.P" FLOWLBL="
                     * l.Cg(integer, "nf_flowlbl")
                     * l.P" "
                     * (
                         netfilter_tcp
                       + netfilter_udp
                       + netfilter_icmpv6
                       + netfilter_other
                       )
prog_grammar["kernel"] = l.Ct(
                      (
                          l.P"["
                        * l.Cg(float, "monotonic_timestamp")
                        * l.P"] "
                        * capture_until("nf_prefix", "IN=")
                        * l.P"IN="
                        * l.Cg(notspace, "nf_in_interface")
                        * l.P" OUT="
                        * l.Cg(notspace, "nf_out_interface")
                        * (
                            l.P" MAC="
                          * l.Cg(commonmac, "nf_dst_mac")
                          * l.P":"
                          * l.Cg(commonmac, "nf_src_mac")
                          )^-1
                        * (
                            netfilter_ipv4
                          + netfilter_ipv6
                          )
                        * (
                            l.P"UID="
                          * l.Cg(integer, "nf_uid")
                          * l.P" GID="
                          * l.Cg(integer, "nf_gid")
                          * l.P" "
                          )^-1
                        * (
                            l.P"MARK="
                          * l.Cg(notspace, "nf_mark")
                          * l.P" "
                          )^-1
                      ))
-- programname=login
prog_grammar["login"] = l.Ct(
                      (
                          l.P"FAILED LOGIN ("
                        * l.Cg(l.digit^1 / tonumber, "failcount")
                        * l.P")"
                        * l.P" on '"
                        * capture_followed_by("tty", "'")
                        * (l.P" from '" * capture_followed_by("from", "'"))^-1
                        * l.P" FOR '"
                        * capture_followed_by("user", "', ")
                        * l.Cg(l.P(1)^1, "pam_error")
                      ) + (
                          l.P"ROOT LOGIN "
                        * l.P" on '"
                        * capture_followed_by("tty", "'")
                        * (l.P" from '" * capture_followed_by("from", "'"))^-1
                        * l.P(-1)
                      ))

-- programname=named
prog_grammar["named"] = l.Ct(
                      ( -- "lame server resolving "%s" (in "%s"?): %s"
                           l.Cg(l.P"lame server", "dns_error")
                        * l.P" resolving '"
                        * capture_followed_by("dns_name", "' (in '")
                        * capture_followed_by("dns_domain", "'?): ")
                        * l.Cg(ipv46, "dns_addr")
                        * l.P"#"
                        * l.Cg(l.digit^1 / tonumber, "dns_port")
                        * l.P(-1)
                      ) + ( -- "error (%s%s%s) resolving "%s/%s/%s": %s" before 1d761cb453c76353deb8423c78e98d00c5f86ffa
                          l.P"error ("
                        * capture_followed_by("dns_error", ") resolving '")
                        * capture_followed_by("dns_name", "/")
                        * capture_followed_by("dns_type", "/")
                        * capture_followed_by("dns_class", "': ")
                        * l.Cg(ipv46, "dns_addr")
                        * l.P"#"
                        * l.Cg(l.digit^1 / tonumber, "dns_port")
                        * l.P(-1)
                      ) + ( -- "%s%s%s resolving "%s/%s/%s": %s" after 1d761cb453c76353deb8423c78e98d00c5f86ffa
                          capture_followed_by("dns_error", " resolving '")
                        * capture_followed_by("dns_name", "/")
                        * capture_followed_by("dns_type", "/")
                        * capture_followed_by("dns_class", "': ")
                        * l.Cg(ipv46, "dns_addr")
                        * l.P"#"
                        * l.Cg(l.digit^1 / tonumber, "dns_port")
                        * l.P(-1)
                      ) + ( -- "DNS format error from %s resolving %s%s%s: %s"
                           l.Cg(l.P"DNS format error", "dns_error")
                        * l.P" from "
                        * l.Cg(ipv46, "dns_addr")
                        * l.P"#"
                        * l.Cg(l.digit^1 / tonumber, "dns_port")
                        * l.P" resolving "
                        * capture_followed_by("dns_name", "/")
                        * capture_until("dns_type", l.P" for client " + l.P":")
                        * (l.P" for client "
                          * l.Cg(ipv46, "dns_client_addr")
                          * l.P"#"
                          * l.Cg(l.digit^1 / tonumber, "dns_client_port")
                          )^-1
                        * l.P": "
                        * l.Cg(l.P(1)^1, "dns_message")
                      ) + ( -- "skipping nameserver '%s' because it is a CNAME, while resolving '%s'"
                           l.Cg(l.P"skipping nameserver", "dns_error")
                        * l.P" '"
                        * capture_followed_by("dns_nameserver", "' because it is a CNAME, while resolving '")
                        * capture_followed_by("dns_name", "'")
                        * l.P(-1)
                      ) + ( -- "client %s%s%s%s%s%s%s%s: %s"
                          l.P"client "
                        * l.Cg(ipv46, "dns_client_addr")
                        * l.P"#"
                        * l.Cg(l.digit^1 / tonumber, "dns_client_port")
                        * (l.P"/key " * l.Cg((l.P(1)-l.S" :")^1, "dns_client_signer"))^-1
                        * (l.P" (" * l.Cg((l.P(1)-l.P")")^1, "dns_name") * l.P")")^-1
                        * (l.P": view " * l.Cg((l.P(1)-l.P": ")^1, "dns_view"))^-1
                        * l.P": "
                        * l.Cg(l.P(1)^1, "dns_message")
                       ) + ( -- "success resolving "%s" (in "%s"?) after %s"
                          l.P"success resolving '"
                        * capture_followed_by("dns_name", "/")
                        * capture_followed_by("dns_type", "' (in '")
                        * capture_followed_by("dns_domain", "'?) after ")
                        * l.Cg(l.P(1)^1, "dns_message")
                       ) + ( -- "sending notifies (serial %u)"
                          l.P"zone "
                        * capture_followed_by("dns_domain", "/")
                        * capture_followed_by("dns_class", "/")
                        * capture_followed_by("dns_view", ": ")
                        * l.Cg("sending notifies", "dns_message")
                        * l.P" (serial "
                        * l.Cg(l.digit^1 / tonumber, "dns_serial")
                        * l.P")"
                        * l.P(-1)
                       ) + ( -- "clients-per-query decreased to %u"
                          l.P"clients-per-query decreased to "
                        * l.Cg(l.digit^1 / tonumber, "dns_clients_per_query")
                        * l.P(-1)
                       ))

-- programname=puppet-agent
-- see http://docs.puppetlabs.com/puppet/latest/reference/lang_reserved.html#classes-and-defined-types
local puppet_namespace_segment = l.upper
                               * (l.lower + l.digit + l.P"_")^0
local puppet_type = -- example: Mod::Config
                    puppet_namespace_segment
                  * (l.P"::" * puppet_namespace_segment)^0
local puppet_resource = ( -- example: Mod::Config[foo]
                        puppet_type
                      * l.P"["
                      * (l.P(1)-l.P"]")^1
                      * l.P"]"
                      )
local puppet_resource_path = ( -- example: /Stage[main]/Profile_one/Mod::Config[foo]
                             (l.P"/" * (puppet_resource + puppet_type))^1
                           )
--http://docs.puppetlabs.com/puppet/latest/reference/lang_reserved.html#parameters
local puppet_parameter = ( -- example: /Stage[main]/Mod::Config[foo]/ensure
                           (l.lower + l.digit + l.P"_")^1
                         )
local puppet_resource_message_cg = (-- "Triggered "#{callback}" from #{events.length} events"
                                    -- "Would have triggered "#{callback}" from #{events.length} events"
                                   l.Cg((l.P"Would have triggered" * l.Cg(l.Cc(true), "puppet_noop")) + l.P"Triggered", "puppet_msg")
                                 * l.P" '"
                                 * capture_followed_by("puppet_callback","' from ")
                                 * l.Cg(integer, "puppet_events_count")
                                 * l.P" events"
                                 * l.P(-1)
                                 ) + (
                                   l.P"Scheduling "
                                 * capture_followed_by("puppet_callback"," of ") -- most probably "refresh"
                                 * l.Cg(puppet_resource, "puppet_callback_target")
                                 * l.P(-1)
                                 ) + (
                                   l.P"Unscheduling "
                                 * capture_followed_by("puppet_callback"," on ") -- most probably "refresh"
                                 * l.Cg(puppet_resource, "puppet_callback_target")
                                 * l.P(-1)
                                 ) + (
                                   l.P"Filebucketed "
                                 * capture_followed_by("puppet_file_path"," to ")
                                 * capture_followed_by("puppet_bucket"," with sum ")
                                 * capture_followed_by("puppet_file_sum",l.P(-1))
                                 )
local puppet_parameter_message_cg = (
                                    l.P"current_value "
                                  * capture_followed_by("puppet_current_value", ", should be ")
                                  * capture_followed_by("puppet_should_value", " (noop)")
                                  * (l.P" (previously recorded value was " *l.Cg(l.P(1)^1, "puppet_historical_value"))^-1
                                  * l.Cg(l.Cc(true), "puppet_noop")
                                  * l.P(-1)
                                  ) + (
                                    l.Cg(puppet_parameter, "puppet_ensure_parameter")
                                  * l.P" changed '"
                                  * capture_followed_by("puppet_old_value", "' to '")
                                  * capture_followed_by("puppet_new_value", "'" * l.P(-1))
                                  ) + (
                                    l.Cg(l.P"executed successfully", "puppet_change")
                                  * l.P(-1)
                                  )
prog_grammar["puppet-agent"] = l.Ct(
                             (
                                 l.P"("
                               * l.Cg(puppet_resource_path, "puppet_resource_path")
                               * l.P"/"
                               * l.Cg(puppet_parameter, "puppet_parameter")
                               * l.P")"
                               * (
                                   (l.P" " * puppet_parameter_message_cg)
                                 + l.P(1)^0 -- parameter can send arbitrary message
                                 )
                             ) + (
                                 l.P"("
                               * capture_followed_by("puppet_resource_path", ") ")
                               * puppet_resource_message_cg
                             ) + (-- msg + (" in %0.2f seconds" % seconds)
                                 l.Cg(l.P"Finished catalog run", "puppet_msg")
                               * l.P" in "
                               * l.Cg(float, "puppet_benchmark_seconds")
                               * l.P" seconds"
                               * l.P(-1)
                             ) + ( -- Keep as is
                                 (l.P"Retrieving pluginfacts" * l.P(-1))
                               + (l.P"Retrieving plugin" * l.P(-1))
                               + (l.P"Loading facts" * l.P(-1))
                               + (l.P"Caching catalog for ")
                               + (l.P"Applying configuration version '")
                               + (l.P"Computing checksum on file ")
                               + (l.P"Run of Puppet configuration client already in progress; skipping (") -- /var/lib/puppet/state/agent_catalog_run.lock exists)
                             ))
-- programname=sshd
prog_grammar["sshd"] = l.Ct(
                     (
                         l.Cg(l.P"Accepted" + l.P"Failed" + l.P"Partial" + l.P"Postponed", "sshd_authmsg")
                       * l.P" "
                       * l.Cg((l.P(1)-l.S"/ ")^1, "sshd_method")
                       * (l.P"/" * l.Cg((l.P(1)-l.S"/ ")^1, "sshd_submethod"))^-1
                       * l.P" for "
                       * l.P"invalid user "^-1
                       * capture_followed_by("remote_user", " from ")
                       * l.Cg(ipv46, "remote_addr")
                       * l.P" port "
                       * l.Cg(l.digit^1 / tonumber, "remote_port")
                       * l.P" "
                       * (l.P"ssh2" + l.P"ssh1")
                       * (l.P": " * l.Cg(l.P(1)^1, "sshd_info"))^-1
                     ) + (
                         l.P"Received disconnect from "
                       * l.Cg(ipv46, "remote_addr")
                       * l.P": "
                       * (l.Cg(l.digit^1 / tonumber, "disconnect_reason") * l.P": ")^-1
                       * l.Cg(l.P(1)^1, "disconnect_msg")
                     ) + (
                         l.P"reverse mapping checking getaddrinfo for "
                       * capture_followed_by("remote_host", "[")
                       * l.Cg(ipv46, "remote_addr")
                       * l.P"] failed - POSSIBLE BREAK-IN ATTEMPT!"
                       * l.P(-1)
                     ) + (
                         l.P"subsystem request for "
                       * capture_followed_by("sshd_subsystem", " by user " + l.P(-1))
                       * l.Cg((l.P(1)-l.S" ")^0, "remote_user")
                       * l.P(-1)
                     ) + (
                         l.P"Connection closed by "
                       * l.Cg(ipv46, "remote_addr")
                       * l.P" [preauth]"
                       * l.P(-1)
                     ) + (
                         l.P"Invalid user "
                       * capture_followed_by("remote_user", " from ")
                       * l.Cg(ipv46, "remote_addr")
                       * l.P(-1)
                     ) + (
                         l.P"input_userauth_request: invalid user "
                       * capture_followed_by("remote_user", " [preauth]")
                       * l.P(-1)
                     ) + (
                         l.P"Exiting on signal "
                       * l.Cg(l.digit^1, "signal")
                       * l.P(-1)
                     ) + (
                         l.P"Received signal "
                       * l.Cg(l.digit^1, "signal")
                       * l.P"; terminating."
                       * l.P(-1)
                     ) + (
                         l.P"Server listening on "
                       * l.Cg((l.P(1)-l.S" ")^1, "listen_address")
                       * l.P" port "
                       * l.Cg(l.digit^1, "listen_port")
                       * l.P"."
                       * l.P(-1)
                     ) + (
                         l.P"Did not receive identification string from "
                       * l.Cg(ipv46, "remote_addr")
                       * l.P(-1)
                     ) + (
                         l.Cg(l.P"error" + l.P"fatal", "sshd_errorlevel")
                       * l.P": "
                       * l.Cg(l.P(1)^1, "sshd_error")
                     ))

-- programname=su
prog_grammar["su"] = l.Ct(
                   (
                       l.Cg(l.P"Successful" + l.P"FAILED", "su_status")
                     * l.P" su for "
                     * capture_followed_by("su_name", " by ")
                     * l.Cg(l.P(1)^1, "su_oldname")
                   ) + (
                       l.P"pam_authenticate: "
                     * l.Cg(l.P(1)^1, "pam_error")
                   ) + (
                       l.S"+-"
                     * l.P" " -- FIXME what to capture?
                   ))

-- programname=sudo
local function sudo_field(name)
    return (l.P(name) * l.P"=" * capture_followed_by("sudo_" .. string.lower(name), " ; "))^-1
end
prog_grammar["sudo"] = l.Ct(
                       capture_followed_by("sudo_message", l.P" : ")
                     * sudo_field("TTY")
                     * sudo_field("PWD")
                     * sudo_field("USER")
                     * sudo_field("GROUP")
                     * sudo_field("TSID")
                     * sudo_field("ENV")
                     * l.P"COMMAND=" * l.Cg(l.P(1)^1, "sudo_command")
                     )

-- programname=systemd-logind
prog_grammar["systemd-logind"] = l.Ct(
                               (
                                 l.P"New session "
                               * l.P"c"^-1 * l.Cg(integer, "session_id")
                               * l.P" of user "
                               * capture_followed_by("user_id", "." * l.P(-1))
                               * l.Cg(l.Cc("SESSION_START"), "sd_message")
                               ) + (
                                 l.P"Removed session "
                               * l.P"c"^-1 * l.Cg(integer, "session_id")
                               * l.P"."
                               * l.Cg(l.Cc("SESSION_STOP"), "sd_message")
                               * l.P(-1)
                               ))

-- programname=useradd
prog_grammar["useradd"] = l.Ct(
                        (
                            l.P"new user: name="
                          * capture_followed_by("user_name", ", UID=")
                          * l.Cg(l.digit^1 / tonumber, "uid")
                          * l.P", GID="
                          * l.Cg(l.digit^1 / tonumber, "gid")
                          * l.P", home="
                          * capture_followed_by("user_home", ", shell=")
                          * l.Cg(l.P(1)^1, "user_shell")
                        ) + (
                            l.P"add '"
                          * capture_followed_by("user_name", l.P"' to group '" + l.P"' to shadow group '")
                          * capture_followed_by("group_name", "'")
                          * l.P(-1)
                        ))

-- PAM
local pam_header = capture_followed_by("pam_module", "(")
                 * capture_followed_by("pam_service", ":")
                 * capture_followed_by("pam_type", "): ")
wildcard_grammar["PAM"] = l.Ct(
                        (   pam_header
                          * l.Cg(l.P"session opened", "pam_action")
                          * l.P" for user "
                          * capture_followed_by("user_name", " by ")
                          * capture_followed_by("login_name", "(uid=")
                          * l.Cg(l.digit^1 / tonumber, "uid")
                          * l.P")"
                        ) + (
                            pam_header
                          * l.Cg(l.P"session closed", "pam_action")
                          * l.P" for user "
                          * l.Cg(l.P(1)^1, "user_name")
                        ) + (
                            pam_header
                          * l.Cg(l.P"authentication failure", "pam_action")
                          * l.P"; logname="
                          * capture_followed_by("logname", " uid=")
                          * l.Cg(l.digit^1 / tonumber, "uid")
                          * l.P" euid="
                          * l.Cg(l.digit^1 / tonumber, "euid")
                          * l.P" tty="
                          * capture_followed_by("tty", " ruser=")
                          * capture_followed_by("ruser", " rhost=")
                          * l.Cg((l.P(1) - l.P("  user="))^0, "rhost")
                          * l.P" " -- duplicate space
                          * (l.P" user=" * l.Cg(l.P(1)^1, "user"))^-1
                        ) + (
                            pam_header
                          * l.P"check pass; user "
                          * (l.P"(" * capture_followed_by("user_name", ") "))^-1
                          * l.P"unknown"
                        ))


function get_prog_grammar(prog)
    return prog_grammar[prog]
end


function get_wildcard_grammar(prog)
    return wildcard_grammar[prog]
end

return M
