-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local results = {
    {
        {
            summary     = "SIMUSE riker %[US/%d+]%->%[GB/%d+]%->%[US/%d+] GB%?",
            recipients  = { "<riker@mozilla.com>" },
            payload     = "^bastion%.host src 216%.160%.83%.56 %(t %- %d+s%) %[US]\n" ..
                "bastion%.host src 81%.2%.69%.192 %(t %- %d+s%) %[GB]\n" ..
                "bastion%.host src 216%.160%.83%.56 %(t=%d+%) %[US]"
        }
    },
    {
        {
            summary     = "SIMUSE riker %[US/%d+]%->%[GB/%d+]%->%[US/%d+] GB%?",
            recipients  = { "<riker@mozilla.com>" },
            payload     = "^bastion%.host src 216%.160%.83%.56 %(t %- %d+s%) %[US]\n" ..
                "bastion%.host src 81%.2%.69%.192 %(t %- %d+s%) %[GB]\n" ..
                "bastion%.host src 216%.160%.83%.56 %(t=%d+%) %[US]"
        },
        {
            summary     = "SIMUSE riker %[US/%d+]%->%[GB/%d+]%->%[US/%d+] GB%?",
            recipients  = { "<riker@mozilla.com>" },
            payload     = "^bastion%.host src 216%.160%.83%.56 %(t %- %d+s%) %[US]\n" ..
                "bastion%.host src 81%.2%.69%.192 %(t %- %d+s%) %[GB]\n" ..
                "bastion%.host src 216%.160%.83%.56 %(t=%d+%) %[US]"
        }
    },
    {
        {
            summary     = "SIMUSE riker %[US/%d+]%->%[GB/%d+]%->%[US/%d+] GB%?",
            recipients  = { "<riker@mozilla.com>" },
            payload     = "^bastion%.host src 216%.160%.83%.56 %(t %- %d+s%) %[US]\n" ..
                "bastion%.host src 81%.2%.69%.192 %(t %- %d+s%) %[GB]\n" ..
                "bastion%.host src 216%.160%.83%.56 %(t=%d+%) %[US]\n\n" ..
                "interim: bastion%.host src 89%.160%.20%.128 %(t %- %d+s%) %[SE]"
        }
    }
}

local cnt = { 1, 1, 1 }

function process_message()
    local summary       = read_message("Fields[summary]") or error("no summary field")
    local first_recip   = read_message("Fields[email.recipients]")
    local secon_recip   = read_message("Fields[email.recipients]", 0, 1)
    local payload       = read_message("Payload")
    local logger        = read_message("Logger")

    local tnum = tonumber(string.match(logger, "analysis.simuse_(%d)"))
    if not tnum then return 1, "invalid logger value" end

    local comp = results[tnum][cnt[tnum]]

    if not string.match(summary, comp.summary) then
        error(string.format("test:%d cnt:%d %s", tnum, cnt[tnum], summary))
    end

    if first_recip ~= comp.recipients[1] then
        error(string.format("test:%d cnt:%d %s", tnum, cnt[tnum], first_recip))
    end
    if secon_recip and secon_recip ~= comp.recipients[2] then
        error(string.format("test:%d cnt:%d %s", tnum, cnt[tnum], secon_recip))
    end

    if not string.match(payload, comp.payload) then
        error(string.format("test:%d cnt:%d %s", tnum, cnt[tnum], payload))
    end

    cnt[tnum] = cnt[tnum] + 1

    return 0
end


function timer_event()
    for i,v in ipairs(cnt) do
        assert(v - 1 == #results[i], string.format("test:%d %d out of %d tests ran", i, v - 1, #results[i]))
    end
end
