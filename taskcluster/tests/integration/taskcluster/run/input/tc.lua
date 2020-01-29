-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "string"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder("decoders.taskcluster.live_backing_log")

local send_decode_failures  = true

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local dh = {Fields = {exchange = {value = {"integration_test"}}, filename = ""}}
function process_message()
    local cnt = 0
    local fh = assert(io.open("tests.txt", "rb"))
    for jfn in fh:lines() do
        local jfh = assert(io.open(jfn, "rb"))
        local data = jfh:read("*a")
        jfh:close()
        dh.Fields.filename = jfn:match("(.+)_pulse.json$")
        local ok, err = pcall(decode, data, dh)
        if (not ok or err) and send_decode_failures then
            err_msg.Payload = err
            err_msg.Fields.data = data
            pcall(inject_message, err_msg)
        end
        cnt = cnt + 1
    end
    return 0, string.format("processed %d jobs", cnt)
end
