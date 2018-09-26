-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "gcp.logging"
require "os"

local log_entry = {
    logName = "projects/logging-poc/logs/test",
    timestamp   = (os.time() - 5) * 1e9,
    severity    = 3,
    insertId    = "12345678-1234-1234-1234-123456789012",

    resource = {
        type    = "gce_instance",
        labels  = {
            instance_id = "7763536380591679470",
            zone        = "us-east1-b"
        }
    },

    httpRequest = {
        requestMethod       = "GET",
        requestUrl          = "/",
        requestSize         = 123,
        status              = 200,
        responseSize        = 2322,
        userAgent           = "Mozilla/4.0 (compatible; MSIE 6.0; Windows 98; Q312461; .NET CLR 1.0.3705)",
        remoteIp            = "192.168.1.1",
        serverIp            = "127.0.0.1",
        referer             = "-",
        latency             = 123000,
        cacheLookup         = true,
        cacheHit            = true,
        cacheValidatedWithOriginServer = true,
        cacheFillBytes      = 344,
        protocol            = "HTTP/1.1"
        },

    labels = {
        foo = "bar"
        },

    operation = {
        id          = "op_id",
        producer    = "producer_name",
        last        = true
        },

    trace           ="projects/my-projectid/traces/06796866738c859f2f19b7cfb3214824",
    span_id         ="000000000000004a",

    sourceLocation = {
        file        = "foo.h",
        line        = 993,
        ["function"]= "escape"
        },

    textPayload = "text payload"
}


local writer = gcp.logging.writer("logging.googleapis.com", 0, 1)
function process_message()
    local ok, status_code, err = pcall(writer.send_sync, writer, log_entry)
    if not ok then return -1, status_code end
    if status_code == 0 then timer = false end
    return status_code, err
end

function timer_event(ns, shutdown)
end
