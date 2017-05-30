-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux sshd Grammar Module

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
    (
        l.Cg(l.P"Accepted" + l.P"Failed" + l.P"Partial" + l.P"Postponed", "sshd_authmsg")
          * l.P" "
          * l.Cg((l.P(1)-l.S"/ ")^1, "sshd_method")
          * (l.P"/" * l.Cg((l.P(1)-l.S"/ ")^1, "sshd_submethod"))^-1
          * l.P" for "
          * l.P"invalid user "^-1
          * sl.capture_followed_by("remote_user", " from ")
          * l.Cg(ipv46, "remote_addr")
          * l.P" port "
          * l.Cg(l.digit^1 / tonumber, "remote_port")
          * l.P" "
          * (l.P"ssh2" + l.P"ssh1")
          * (l.P": " * l.Cg(l.P(1)^1, "sshd_info"))^-1
        )
    + (
            l.P"Received disconnect from "
          * l.Cg(ipv46, "remote_addr")
          * l.P": "
          * (l.Cg(l.digit^1 / tonumber, "disconnect_reason") * l.P": ")^-1
          * l.Cg(l.P(1)^1, "disconnect_msg")
        )
    + (
            l.P"reverse mapping checking getaddrinfo for "
          * sl.capture_followed_by("remote_host", "[")
          * l.Cg(ipv46, "remote_addr")
          * l.P"] failed - POSSIBLE BREAK-IN ATTEMPT!"
          * l.P(-1)
        )
    + (
            l.P"subsystem request for "
          * sl.capture_followed_by("sshd_subsystem", " by user " + l.P(-1))
          * l.Cg((l.P(1)-l.S" ")^0, "remote_user")
          * l.P(-1)
        )
    + (
            l.P"Connection closed by "
          * l.Cg(ipv46, "remote_addr")
          * l.P" [preauth]"
          * l.P(-1)
        )
    + (
            l.P"Invalid user "
          * sl.capture_followed_by("remote_user", " from ")
          * l.Cg(ipv46, "remote_addr")
          * l.P(-1)
        )
    + (
            l.P"input_userauth_request: invalid user "
          * sl.capture_followed_by("remote_user", " [preauth]")
          * l.P(-1)
        )
    + (
            l.P"Exiting on signal "
          * l.Cg(l.digit^1, "signal")
          * l.P(-1)
        )
    + (
            l.P"Received signal "
          * l.Cg(l.digit^1, "signal")
          * l.P"; terminating."
          * l.P(-1)
        )
    + (
            l.P"Server listening on "
          * l.Cg((l.P(1)-l.S" ")^1, "listen_address")
          * l.P" port "
          * l.Cg(l.digit^1, "listen_port")
          * l.P"."
          * l.P(-1)
        )
    + (
            l.P"Did not receive identification string from "
          * l.Cg(ipv46, "remote_addr")
          * l.P(-1)
        )
    + (
            l.Cg(l.P"error" + l.P"fatal", "sshd_errorlevel")
          * l.P": "
          * l.Cg(l.P(1)^1, "sshd_error")
        )
    )

return M
