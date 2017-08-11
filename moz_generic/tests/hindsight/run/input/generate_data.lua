-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for the moz_generic ingestion decoder
--]]

require "string"

local submission = '{"foo":"bar"}'
local uri_prefix = "/submit/generic/test/1/documentid"
local submissions = {
    -- not enough path components
    {"/", submission},
    -- invalid path prefix
    {"/notsubmit/generic/test/1/documentid", submission},
    -- too many path components
    {uri_prefix .. "/too/many/path/components", submission},
    -- path length
    {"/submit/generic/test/1/" .. string.rep("0", 1024), submission},
    -- no schema
    {"/submit/generic/test/2/documentid", submission},
    -- -- no schema, special characters
    -- {"/submit/@!@$@/test/2/documentid", submission},
    -- schema validation failure (missing required foo)
    {uri_prefix, "{}"},
    -- schema validation failure (bad type for foo)
    {uri_prefix, '{"foo":1}'},
    -- bad json
    {uri_prefix, '{'},
    -- valid submission and duplicate
    {uri_prefix, submission, true},
}

local msg = {
    Logger = "moz_ingest",
    Type   = "default",
    Hostname = "test.moz_generic.com",
    Fields = {
        remote_addr = "8.8.8.8",
        uri         = nil,
        protocol    = "HTTPS"
    }
}

function process_message()
    for i,v in ipairs(submissions) do
        local uri, content, duplicate = unpack(v)
        local id = ""
        if string.match(uri, "documentid") then id = tostring(i) end
        msg.Fields.uri = string.gsub(uri, "documentid", "documentid" .. id)
        msg.Fields.content = content
        inject_message(msg)
        if duplicate then inject_message(msg) end
    end

    return 0
end
