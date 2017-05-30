-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux named Grammar Module

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

local ipv46 = ip.v4_field + ip.v6_field

syslog_grammar = l.Ct(
    (   -- "lame server resolving "%s" (in "%s"?): %s"
        l.Cg(l.P"lame server", "dns_error")
        * l.P" resolving '"
        * sl.capture_followed_by("dns_name", "' (in '")
        * sl.capture_followed_by("dns_domain", "'?): ")
        * l.Cg(ipv46, "dns_addr")
        * l.P"#"
        * l.Cg(l.digit^1 / tonumber, "dns_port")
        * l.P(-1)
        )
    + ( -- "error (%s%s%s) resolving "%s/%s/%s": %s" before 1d761cb453c76353deb8423c78e98d00c5f86ffa
        l.P"error ("
        * sl.capture_followed_by("dns_error", ") resolving '")
        * sl.capture_followed_by("dns_name", "/")
        * sl.capture_followed_by("dns_type", "/")
        * sl.capture_followed_by("dns_class", "': ")
        * l.Cg(ipv46, "dns_addr")
        * l.P"#"
        * l.Cg(l.digit^1 / tonumber, "dns_port")
        * l.P(-1)
        )
    + ( -- "%s%s%s resolving "%s/%s/%s": %s" after 1d761cb453c76353deb8423c78e98d00c5f86ffa
        sl.capture_followed_by("dns_error", " resolving '")
        * sl.capture_followed_by("dns_name", "/")
        * sl.capture_followed_by("dns_type", "/")
        * sl.capture_followed_by("dns_class", "': ")
        * l.Cg(ipv46, "dns_addr")
        * l.P"#"
        * l.Cg(l.digit^1 / tonumber, "dns_port")
        * l.P(-1)
        ) 
    + ( -- "DNS format error from %s resolving %s%s%s: %s"
        l.Cg(l.P"DNS format error", "dns_error")
        * l.P" from "
        * l.Cg(ipv46, "dns_addr")
        * l.P"#"
        * l.Cg(l.digit^1 / tonumber, "dns_port")
        * l.P" resolving "
        * sl.capture_followed_by("dns_name", "/")
        * sl.capture_until("dns_type", l.P" for client " + l.P":")
        * (l.P" for client "
           * l.Cg(ipv46, "dns_client_addr")
           * l.P"#"
           * l.Cg(l.digit^1 / tonumber, "dns_client_port")
           )^-1
        * l.P": "
        * l.Cg(l.P(1)^1, "dns_message")
        ) 
    + ( -- "skipping nameserver '%s' because it is a CNAME, while resolving '%s'"
        l.Cg(l.P"skipping nameserver", "dns_error")
        * l.P" '"
        * sl.capture_followed_by("dns_nameserver", "' because it is a CNAME, while resolving '")
        * sl.capture_followed_by("dns_name", "'")
        * l.P(-1)
        )
    + ( -- "client %s%s%s%s%s%s%s%s: %s"
        l.P"client "
        * l.Cg(ipv46, "dns_client_addr")
        * l.P"#"
        * l.Cg(l.digit^1 / tonumber, "dns_client_port")
        * (l.P"/key " * l.Cg((l.P(1)-l.S" :")^1, "dns_client_signer"))^-1
        * (l.P" (" * l.Cg((l.P(1)-l.P")")^1, "dns_name") * l.P")")^-1
        * (l.P": view " * l.Cg((l.P(1)-l.P": ")^1, "dns_view"))^-1
        * l.P": "
        * l.Cg(l.P(1)^1, "dns_message")
        )
    + ( -- "success resolving "%s" (in "%s"?) after %s"
        l.P"success resolving '"
        * sl.capture_followed_by("dns_name", "/")
        * sl.capture_followed_by("dns_type", "' (in '")
        * sl.capture_followed_by("dns_domain", "'?) after ")
        * l.Cg(l.P(1)^1, "dns_message")
        )
    + ( -- "sending notifies (serial %u)"
        l.P"zone "
        * sl.capture_followed_by("dns_domain", "/")
        * sl.capture_followed_by("dns_class", "/")
        * sl.capture_followed_by("dns_view", ": ")
        * l.Cg("sending notifies", "dns_message")
        * l.P" (serial "
        * l.Cg(l.digit^1 / tonumber, "dns_serial")
        * l.P")"
        * l.P(-1)
        ) 
    + ( -- "clients-per-query decreased to %u"
        l.P"clients-per-query decreased to "
        * l.Cg(l.digit^1 / tonumber, "dns_clients_per_query")
        * l.P(-1)
        )
    )

return M
