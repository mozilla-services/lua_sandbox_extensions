-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"

local captures = {""}
local results = {
    {type = 'error.log.schema', error_message = 'unclosed block'},
    {type = 'error.decode', error_message = '...io_modules/decoders/taskcluster/live_backing_log.lua:666: Expected value but found T_OBJ_END at character 1'},
    {type = 'error.perfherder.parse', error_message = '...io_modules/decoders/taskcluster/live_backing_log.lua:128: Expected comma or object end but found T_COLON at character 21'},
    {type = 'error.perfherder.validation', error_message = 'SchemaURI: #/properties/suites/items Keyword: additionalProperties DocumentURI: #/suites/0/extraField'},
    {type = 'error.decode', error_message = '...io_modules/decoders/taskcluster/live_backing_log.lua:743: missing.log: No such file or directory'}
}

local cnt = 0
function process_message()
    local t = read_message("Type")
    local m = read_message("Payload")
    cnt = cnt + 1

    local e = results[cnt].type
    if t ~= e then error(string.format("test: %d file expected: %s received: %s", cnt, tostring(e), tostring(t))) end

    e = results[cnt].error_message
    if m ~= e then error(string.format("test: %d file expected: %s received: %s", cnt, tostring(e), tostring(m))) end

    captures[#captures + 1] = string.format("{type = '%s', error_message = '%s'}", t, m)
    return 0
end

function timer_event(ns)
    inject_payload("txt", "captures", table.concat(captures, ",\n"))
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end
