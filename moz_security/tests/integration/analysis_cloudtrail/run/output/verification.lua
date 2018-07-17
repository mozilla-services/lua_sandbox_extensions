-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local results = {
    "access key created in prod",
    "IAM action in production account from console without mfa in prod"
}

local cnt = 1

function process_message()
    local summary   = read_message("Fields[summary]") or error("no summary field")
    local r         = read_message("Fields[email.recipients]") or error("no recipients field")

    if summary ~= results[cnt] then
        error(string.format("test cnt:%d %s", cnt, summary))
    end
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt-1 == #results, string.format("test %d out of %d tests ran", cnt-1, #results))
end
