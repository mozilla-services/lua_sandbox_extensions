-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_security_sshd_login alerts
--]]

require "string"

-- Validate normal configuration, default email + manatee
local results = {
    { summary    = "trink logged into bastion from 192.168.1.1",
      recipients = {"<foxsec-dump+OutOfHours@mozilla.com>", "<manatee-trink@moz-svc-ops.pagerduty.com>"}
    },
    { summary    = "trink logged into bastion from 192.168.1.2 (Mountain View, US)",
      recipients = {"<foxsec-dump+OutOfHours@mozilla.com>", "<manatee-trink@moz-svc-ops.pagerduty.com>"}
    },
}

-- Validate alternate configuration, modified default and no manatee append
local results_only_default = {
    { summary    = "trink logged into bastion from 192.168.1.1",
      recipients = {"<foxsec-alternate+OutOfHours@mozilla.com>"}
    },
    { summary    = "trink logged into bastion from 192.168.1.2 (Mountain View, US)",
      recipients = {"<foxsec-alternate+OutOfHours@mozilla.com>"}
    },
}

local resset = {}
if read_config("only_default_email") then
    resset = results_only_default
else
    resset = results
end

local cnt = 0


function process_message()
    local summary = read_message("Fields[summary]") or error("no summary field")
    local dflt_recip = read_message("Fields[email.recipients]") or error("no email recipients")
    local user_recip = read_message("Fields[email.recipients]", 0, 1) or nil

    cnt = cnt + 1
    local er = resset[cnt]
    assert(er, "too many messages")

    if er.summary ~= summary then
        error(string.format("test:%d result:%s", cnt, summary))
    end
    if er.recipients[1] ~= dflt_recip then
        error(string.format("test:%d result:%s", cnt, dflt_recip))
    end
    if #er.recipients > 1 then
        assert(er.recipients[2], "no user recipient in test case")
        if er.recipients[2] ~= user_recip then
            error(string.format("test:%d result:%s", cnt, user_recip))
        end
    end
    return 0
end


function timer_event()
    assert(cnt == 2, string.format("%d out of 2 tests ran", cnt))
end
