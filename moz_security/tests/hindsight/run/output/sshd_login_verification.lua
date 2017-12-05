-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_security_sshd_login alerts
--]]

require "string"

local results = {
    { summary    = "trink logged into bastion from 192.168.1.1 id:11111111111111111111111111111111",
      recipients = {"<foxsec-alerts@mozilla.com>", "<manatee-trink@moz-svc-ops.pagerduty.com>"}
    }
}

local cnt = 0
function process_message()
    local summary = read_message("Fields[summary]") or "nil"
    local dflt_recip = read_message("Fields[email.recipients]") or "nil"
    local user_recip = read_message("Fields[email.recipients]", 0, 1) or "nil"
    cnt = cnt + 1
    local er = results[cnt]
    assert(er, "too many messages")

    if er.summary ~= summary then
        error(string.format("test:%d result:%s", cnt, summary))
    end
    if er.recipients[1] ~= dflt_recip then
        error(string.format("test:%d result:%s", cnt, dflt_recip))
    end
    if er.recipients[2] ~= user_recip then
        error(string.format("test:%d result:%s", cnt, user_recip))
    end
    return 0
end


function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end
