-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.sendmail".grammar
local log
local fields

log = 'x63EUUUUUUU111: to=<someone@xs4all.nl>, delay=12:34:45, xdelay=00:00:00, mailer=lmtp, pri=128179, relay=imap.xs4all.nl [194.109.6.110], dsn=2.0.0, stat=Sent'
fields = grammar:match(log)
assert(fields.sendmailid == 'x63EUUUUUUU111', fields.sendmailid)
assert(fields.to == '<someone@xs4all.nl>', fields.to)
assert(fields.delay == '12:34:45', fields.delay)
assert(fields.xdelay == '00:00:00', fields.xdelay)
assert(fields.mailer == 'lmtp', fields.mailer)
assert(fields.pri == '128179', fields.pri)
assert(fields.relay == 'imap.xs4all.nl [194.109.6.110]', fields.relay)
assert(fields.dsn == '2.0.0', fields.dsn)
assert(fields.stat == 'Sent', fields.stat)

log = 'x63EUUUUUUU111: from=<postmaster@example.com>, size=1234, class=0, nrcpts=1, msgid=<20190101120033.1234@example.com>, proto=ESMTP, daemon=MTA, relay=remote.example.com [192.168.1.1]'
fields = grammar:match(log)
assert(fields.sendmailid == 'x63EUUUUUUU111', fields.sendmailid)
assert(fields.from == '<postmaster@example.com>', fields.from)
assert(fields.size == '1234', fields.size)
assert(fields.class == '0', fields.size)
assert(fields.nrcpts == '1', fields.nrcpts)
assert(fields.msgid == '<20190101120033.1234@example.com>', fields.msgid)
assert(fields.proto == 'ESMTP', fields.proto)
assert(fields.daemon == 'MTA', fields.daemon)
assert(fields.relay == 'remote.example.com [192.168.1.1]', fields.relay)
