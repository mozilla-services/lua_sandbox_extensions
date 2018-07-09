-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local results = {
    { "duo bypass code creation for user worf", nil },
    { "duo new user created worf", nil },
    { "duo phone call factor rejected for user worf", nil },
    { "duo phone call factor rejected for user gowron", nil },
    { "duo fraud flag on authentication for user gowron", nil },
    { "duo admin_2fa_error on console access for user Admin User", nil },
    { "duo admin integration added or modified by user admin acct", nil },
    { "duo admin integration added or modified by user admin acct 2", nil },
    { "duo admin user New User added or modified by user admin acct", nil },
    { "duo admin user New User 2 added or modified by user New User 2", nil },
    {
        "duo anomalous push recorded for user user",
        '{"event_device":"000-000-0000","event_location_state":"State","event_ip":"0.0.0.0",' ..
        '"event_factor":"Duo Push","event_result":"FAILURE","event_reason":"Anomalous push",' ..
        '"event_timestamp":1516913653,"event_location_country":"US","event_username":"user",' ..
        '"event_location_city":"City","event_integration":"SSH Access"}',
    }

}

local cnt = 1

function process_message()
    local summary   = read_message("Fields[summary]") or error("no summary field")
    local r         = read_message("Fields[email.recipients]") or error("no recipients field")
    local payload   = read_message("Payload")

    if summary ~= results[cnt][1] then
        error(string.format("test cnt:%d %s", cnt, summary))
    end
    if results[cnt][2] and payload ~= results[cnt][2] then
        error(string.format("test cnt:%d %s", cnt, payload))
    end
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt-1 == #results, string.format("test %d out of %d tests ran", cnt-1, #results))
end
