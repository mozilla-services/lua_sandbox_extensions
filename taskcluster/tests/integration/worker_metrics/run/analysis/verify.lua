-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local results = {
    [[{"workerPoolId":"aws-provisioner-v1\/gecko-1-b-win2012-beta","workerId":"i-00bd3e057cf8555f6","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":"2019-10-14T15:39:26.000000000Z","eventType":"instanceBoot","worker":"generic-worker"}]],
    [[{"workerPoolId":"aws-provisioner-v1\/gecko-1-b-win2012-beta","workerId":"i-00bd3e057cf8555f6","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":"2019-10-14T15:43:01.000000000Z","eventType":"workerReady","worker":"generic-worker"}]],
    [[{"workerPoolId":"aws-provisioner-v1\/gecko-1-b-win2012-beta","workerId":"i-00bd3e057cf8555f6","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":"2019-10-14T15:43:16.000000000Z","eventType":"instanceReboot","worker":"generic-worker"}]]
}

local cnt = 0
function process_message()
    cnt = cnt + 1
    local p = read_message("Payload")
    local e = results[cnt]
    if p ~= e then error(string.format("test: %d received: %s expected: %s", cnt, p, e)) end
    return 0
end

function timer_event(ns)
    if cnt ~= #results then error(string.format("messages received: %d expected %d", cnt, #results)) end
end
