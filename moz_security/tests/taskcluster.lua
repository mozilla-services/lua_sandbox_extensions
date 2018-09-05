-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local taskcluster = require "taskcluster"
local string = require "string"

data = {
  {{ Fields = { clientid = "no-user-name" } }, nil},
  {{ Fields = { clientid = "mozilla-auth0/ad|Mozilla|almost/" } }, nil},
  {{ Fields = { clientid = "mozilla-auth0/ad|Mozilla|almost/again" } }, nil},
  {{ Fields = { clientid = "mozilla-auth0/ad|Mozilla-LDAP|picard/" } }, "picard"},
  {{ Fields = { clientid = "mozilla-auth0/ad|Mozilla-LDAP|picard/test" } }, "picard"},
}

for i, msg in ipairs(data) do
  taskcluster.add_username(msg[1], "clientid")

  errmsg = string.format("test cnt:%d failed. %s != %s", i, tostring(msg[1].Fields["username"]), tostring(msg[2]))
  assert(msg[1].Fields["username"] == msg[2], errmsg)
end
