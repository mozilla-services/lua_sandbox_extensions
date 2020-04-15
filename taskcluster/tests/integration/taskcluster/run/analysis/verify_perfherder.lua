-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cjson"
require "string"
require "table"

--local capture_only = true
local captures = {}
local results = {
{framework = 'talos', taskId = 'CZ9BVge4QdKrJ3ZWdVbsTQ'},
{framework = 'job_resource_usage', taskId = 'IViCwC-nTMi_gXPE3ckjPg'},
{framework = 'raptor', taskId = 'USQ8K5YcQJKQgybb28cyXg'},
{framework = 'raptor', taskId = 'USQ8K5YcQJKQgybb28cyXg'},
{framework = 'raptor', taskId = 'USQ8K5YcQJKQgybb28cyXg'},
{framework = 'job_resource_usage', taskId = 'a46tmlKvRFuopDLt8E7IEQ'},
{framework = 'job_resource_usage', taskId = 'CX96USXgR3CvJWA2ZsBYrA'},
{framework = 'vcs', taskId = 'SSXGXyVIRQGQqVKGym90mQ'},
{framework = 'build_metrics', taskId = 'SSXGXyVIRQGQqVKGym90mQ'},
{framework = 'job_resource_usage', taskId = 'AuIAPvWhSiyp0eUh5vAdCw'},
{framework = 'vcs', taskId = 'ZYFKUNR5RhmrBAq4Z4KB9g'},
{framework = 'awsy', taskId = 'B02j0uS8SOGRfB4TrE2q4w'},
{framework = 'browsertime', taskId = 'bZPP4WKDR5Whwge70OcW9g'},
{framework = 'browsertime', taskId = 'aZ19zQ0SS8OLeFnQoHSwNA'},
{framework = 'build_metrics', taskId = 'HbxirNOCRYiM1yUmLBMeYQ'},
{framework = 'raptor', taskId = 'HbxirNOCRYiM1yUmLBMeYQ', recordingDate = "2019-06-19"},
{framework = 'raptor', taskId = 'HbxirNOCRYiM1yUmLBMeYQ', recordingDate = "2019-06-19"},
}

local cnt = 0
function process_message()
    local f = cjson.decode(read_message("Payload"))
    captures[#captures + 1] = string.format("{framework = '%s', taskId = '%s'}", f.framework, f.taskId)
    cnt = cnt + 1

    if capture_only then return 0 end

    local r = f.taskId
    local e = results[cnt].taskId
    if r ~= e then error(string.format("test: %d taskId expected: '%s' received: '%s'", cnt, tostring(e), tostring(r))) end

    r = f.framework
    e = results[cnt].framework
    if r ~= e then error(string.format("test: %d framework expected: '%s' received: '%s'", cnt, tostring(e), tostring(r))) end

    r = f.recordingDate
    e = results[cnt].recordingDate
    if r ~= e then error(string.format("test: %d recordingDate expected: '%s' received: '%s'", cnt, tostring(e), tostring(r))) end

    return 0
end

function timer_event(ns)
    inject_payload("txt", "captures", table.concat(captures, ",\n"))
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end
