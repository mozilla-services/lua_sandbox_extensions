-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"

local captures = {""}
local results = {
    {framework = 'vcs'},
    {framework = 'job_resource_usage'},
    {framework = 'build_metrics'},
    {framework = 'js-bench'},
    {framework = 'devtools'},
    {framework = 'platform_microbench'},
    {framework = 'awsy'},
    {framework = 'raptor'},
    {framework = 'talos'}
}

local cnt = 0
function process_message()
    local f = read_message("Fields[framework]")
    cnt = cnt + 1

    local e = results[cnt].framework
    if f ~= e then error(string.format("test: %d file expected: %s received: %s", cnt, tostring(e), tostring(f))) end

    captures[#captures + 1] = string.format("{framework = '%s'}", f)
    return 0
end

function timer_event(ns)
    inject_payload("txt", "captures", table.concat(captures, ",\n"))
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end
