-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Extensions for Taskcluster

This module is intended to be used with another IO module such as a decoder to
add a username field if the client is a human user.

## Functions

### add_username

Given a Heka message with a Taskcluster clientid, attempt to parse out the username
associated with the clientid. This is currently specific to Mozilla LDAP usernames,
as that is the primary way in which human users authenticate with Taskcluster. If no
username is found, do nothing.

*Arguments*
- msg (table) - original message
- field_name (string) - field name in the message to lookup

*Return*
- none - the message is modified in place if a username is found

## Configuration examples
decoder_module = {
    {
        { "decoders.heka.table_to_fields" },
        { clientid = "taskcluster#add_username"}
    }
}
--]]

local re = require "re"

local M = {}
setfenv(1, M)

function add_username(msg, field_name)
    if not msg.Fields then return end
    local clientid = msg.Fields[field_name]

    username = re.match(clientid, "'mozilla-auth0/ad|Mozilla-LDAP|' (s <- {%w+}) '/'")
    if username then
      msg.Fields["username"] = username
    end
end

return M
