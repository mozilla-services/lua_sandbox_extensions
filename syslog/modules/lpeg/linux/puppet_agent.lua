-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux puppet-agent Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

-- see http://docs.puppetlabs.com/puppet/latest/reference/lang_reserved.html#classes-and-defined-types
local puppet_namespace_segment = l.upper * (l.lower + l.digit + l.P"_")^0
-- example: Mod::Config
local puppet_type = puppet_namespace_segment * (l.P"::" * puppet_namespace_segment)^0
 -- example: Mod::Config[foo]
local puppet_resource = (puppet_type * l.P"[" * (l.P(1)-l.P"]")^1 * l.P"]")
-- example: /Stage[main]/Profile_one/Mod::Config[foo]
local puppet_resource_path = (l.P"/" * (puppet_resource + puppet_type))^1
-- http://docs.puppetlabs.com/puppet/latest/reference/lang_reserved.html#parameters
-- example: /Stage[main]/Mod::Config[foo]/ensure
local puppet_parameter = (l.lower + l.digit + l.P"_")^1

local puppet_resource_message_cg = (
    -- "Triggered "#{callback}" from #{events.length} events"
    -- "Would have triggered "#{callback}" from #{events.length} events"
    l.Cg((l.P"Would have triggered" * l.Cg(l.Cc(true), "puppet_noop")) + l.P"Triggered", "puppet_msg")
    * l.P" '"
    * sl.capture_followed_by("puppet_callback","' from ")
    * l.Cg(sl.integer, "puppet_events_count")
    * l.P" events"
    * l.P(-1)
    )
+ (
    l.P"Scheduling "
    * sl.capture_followed_by("puppet_callback"," of ") -- most probably "refresh"
    * l.Cg(puppet_resource, "puppet_callback_target")
    * l.P(-1)
    )
+ (
    l.P"Unscheduling "
    * sl.capture_followed_by("puppet_callback"," on ") -- most probably "refresh"
    * l.Cg(puppet_resource, "puppet_callback_target")
    * l.P(-1)
    )
+ (
    l.P"Filebucketed "
    * sl.capture_followed_by("puppet_file_path"," to ")
    * sl.capture_followed_by("puppet_bucket"," with sum ")
    * sl.capture_followed_by("puppet_file_sum",l.P(-1))
    )

local puppet_parameter_message_cg = (
    l.P"current_value "
    * sl.capture_followed_by("puppet_current_value", ", should be ")
    * sl.capture_followed_by("puppet_should_value", " (noop)")
    * (l.P" (previously recorded value was " *l.Cg(l.P(1)^1, "puppet_historical_value"))^-1
    * l.Cg(l.Cc(true), "puppet_noop")
    * l.P(-1)
    )
+ (
    l.Cg(puppet_parameter, "puppet_ensure_parameter")
    * l.P" changed '"
    * sl.capture_followed_by("puppet_old_value", "' to '")
    * sl.capture_followed_by("puppet_new_value", "'" * l.P(-1))
    )
+ (
    l.Cg(l.P"executed successfully", "puppet_change")
    * l.P(-1)
    )

syslog_grammar = l.Ct(
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
        )
    + (
        l.P"("
        * sl.capture_followed_by("puppet_resource_path", ") ")
        * puppet_resource_message_cg
        )
    + (  -- msg + (" in %0.2f seconds" % seconds)
         l.Cg(l.P"Finished catalog run", "puppet_msg")
         * l.P" in "
         * l.Cg(sl.float, "puppet_benchmark_seconds")
         * l.P" seconds"
         * l.P(-1)
         )
    + (  -- Keep as is
         (l.P"Retrieving pluginfacts" * l.P(-1))
         + (l.P"Retrieving plugin" * l.P(-1))
         + (l.P"Loading facts" * l.P(-1))
         + (l.P"Caching catalog for ")
         + (l.P"Applying configuration version '")
         + (l.P"Computing checksum on file ")
         + (l.P"Run of Puppet configuration client already in progress; skipping (") -- /var/lib/puppet/state/agent_catalog_run.lock exists)
         )
    )

return M
