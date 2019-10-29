-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local inputs = {
    'UTC WORKER_METRICS {"eventType":"instanceBoot","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":1571067566,"worker":"generic-worker","workerId":"i-00bd3e057cf8555f6","workerPoolId":"aws-provisioner-v1/gecko-1-b-win2012-beta"}',
    'UTC WORKER_METRICS {"eventType":"workerReady","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":1571067781,"worker":"generic-worker","workerId":"i-00bd3e057cf8555f6","workerPoolId":"aws-provisioner-v1/gecko-1-b-win2012-beta"} ',
    'this will be ignored',
    'UTC WORKER_METRICS {"eventType":"instanceReboot","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":1571067796,"worker":"generic-worker","workerId":"i-00bd3e057cf8555f6","workerPoolId":"aws-provisioner-v1/gecko-1-b-win2012-beta" ',
    'UTC WORKER_METRICS {"bogusType":"instanceReboot","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":1571067796,"worker":"generic-worker","workerId":"i-00bd3e057cf8555f6","workerPoolId":"aws-provisioner-v1/gecko-1-b-win2012-beta"} ',
    'UTC WORKER_METRICS {"eventType":"instanceReboot","instanceType":"c4.4xlarge","region":"us-east-1","timestamp":1571067796,"worker":"generic-worker","workerId":"i-00bd3e057cf8555f6","workerPoolId":"aws-provisioner-v1/gecko-1-b-win2012-beta"} '
}


require "string"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder("decoders.taskcluster.worker_metrics")

local send_decode_failures  = true

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

function process_message()
    local cnt = 0
    local msg = {}
    for i,v in ipairs(inputs) do
        local ok, err = pcall(decode, v)
        if (not ok or err) and send_decode_failures then
            err_msg.Payload = err
            err_msg.Fields.data = v
            pcall(inject_message, err_msg)
        end
        cnt = cnt + 1
    end
    return 0, string.format("processed %d metrics", cnt)
end

