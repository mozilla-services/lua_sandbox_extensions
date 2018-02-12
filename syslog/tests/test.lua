-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

assert(loadfile"syslog.lua")()

assert(loadfile"bsd/filterlog.lua")()

assert(loadfile"linux/cron.lua")()
assert(loadfile"linux/dhclient.lua")()
assert(loadfile"linux/dhcpd.lua")()
assert(loadfile"linux/groupadd.lua")()
assert(loadfile"linux/groupdel.lua")()
assert(loadfile"linux/kernel.lua")()
assert(loadfile"linux/login.lua")()
assert(loadfile"linux/named.lua")()
assert(loadfile"linux/pam.lua")()
assert(loadfile"linux/puppet_agent.lua")()
assert(loadfile"linux/sshd.lua")() -- todo deprecate
assert(loadfile"linux/su.lua")()
assert(loadfile"linux/sudo.lua")()
assert(loadfile"linux/systemd_logind.lua")()
assert(loadfile"linux/useradd.lua")()
