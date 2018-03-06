-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_ingest_common decoder
--]]

require "string"

local msg = {
    Logger = "moz_ingest",
    Type   = "json.raw",
    Hostname = "example.com",
    Fields = {
        remote_addr = "216.160.83.56",
        uri         = nil,
    }
}

function process_message()
    -- valid
    msg.Fields.uri = "/submit/foo/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A01"
    msg.Fields.content = [[{"exampleString":"string one"}]]
    msg.Fields["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:59.0) Gecko/20100101 Firefox/59.0"
    inject_message(msg)

    -- fails parsing
    msg.Fields.uri = "/submit/foo/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A02"
    msg.Fields.content = ""
    inject_message(msg)

    -- fails validation
    msg.Fields.uri = "/submit/foo/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A03"
    msg.Fields.content = [[{"xString":"string one"}]]
    inject_message(msg)

    -- fails schema lookup
    msg.Fields.uri = "/submit/bar/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A01"
    msg.Fields.content = "{}"
    inject_message(msg)

    return 0
end
