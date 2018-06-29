-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates sample authentication events for auth_lastx

--]]

require "os"
require "string"

local sdec = require "decoders.syslog"
local cdec = require "decoders.heka.table_to_fields"

-- test table, array indices correspond to analysis and output configurations
local test = {
    {
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "dontmatchme", "Accepted publickey for riker from 10.10.10.10 port 4242 ssh2", sdec, 0 },
        { nil, '{"additionalEventData":{' ..
            '"LoginTo":"https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2",' ..
            '"MFAUsed":"Yes","MobileVersion":"No"},"awsRegion":"us-west-2",' ..
            '"eventID":"00000000-0000-0000-0000-000000000000","eventName":"ConsoleLogin",' ..
            '"eventSource":"signin.amazonaws.com","eventTime":"2018-06-26T06:00:13Z",' ..
            '"eventType":"AwsConsoleSignIn","eventVersion":"1.05","recipientAccountId":"999999999999",' ..
            '"requestParameters":null,"responseElements":{"ConsoleLogin":"Success"},' ..
            '"sourceIPAddress":"10.0.0.1",' ..
            '"userAgent":"Mozilla/5.0(Macintosh;IntelMacOSX10.13;rv:62.0)Gecko/20100101Firefox/62.0",' ..
            '"userIdentity":{"accountId":"999999999999","arn":"arn:aws:iam::999999999999:user/riker",' ..
            '"principalId":"XXXXXXXXXXXXXXXXXXXXX","type":"IAMUser","userName":"riker"}}', cdec, 0 },
        { "sshd", "Accepted publickey for riker from 10.0.0.1 port 4242 ssh2", sdec, 0 },
    }
}

-- default message headers
local msg = {
    Timestamp = nil,
    Logger = nil,
    Hostname = "bastion.host"
}

function process_message()
    for i,v in ipairs(test) do
        msg.Logger = string.format("generate_auth_multi_%d", i)
        for _,w in ipairs(v) do
            local t = os.time() + w[4]
            if w[1] then -- treat as syslog
                local d = os.date("%b %d %H:%M:%S", t)
                w[3].decode(string.format("%s %s %s: %s", d, msg.Hostname, w[1], w[2]), msg, false)
            else -- treat as cloudtrail json data
                w[3].decode(w[2], msg)
            end
        end
    end
    return 0
end
