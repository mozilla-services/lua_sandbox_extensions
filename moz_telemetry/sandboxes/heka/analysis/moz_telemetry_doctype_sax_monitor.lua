-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry docType Submission 'shape' Monitor

## Sample Configuration
```lua
filename = "moz_telemetry_doctype_sax_monitor.lua"
doc_type = "main"
message_matcher = 'Type == "telemetry" && Fields[docType] == "' .. doc_type .. '"'
preserve_data = true
ticker_interval = 60

alert = {
  disabled = false,
  prefix = true,
  throttle = 1439,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    [doc_type] = {
      "AAAAABCEFEEEEFFFFEEDCBBB",
      "AAAABCEFEEEEFFFFEEDCBBBA",
      "AAABCEFEEEEFFFFEEDCBBBAA",
      "AABCEFEEEEFFFFEEDCBBBAAA",
      "ABCEFEEEEFFFFEEDCBBBAAAA",
      "BCEFEEEEFFFFEEDCBBBAAAAA",
      "CEFEEEEFFFFEEDCBBBAAAAAB",
      "EFEEEEFFFFEEDCBBBAAAAABC",
      "FEEEEFFFFEEDCBBBAAAAABCE",
      "EEEEFFFFEEDCBBBAAAAABCEE",
      "EEEFFFFEEDCBBBAAAAABCEEE",
      "EEFFFFEEDCBBBAAAAABCEEEE",
      "EFFFFEEDCBBBAAAAABCEEEEE",
      "FFFFEEDCBBBAAAAABCEEEEEE",
      "FFFEEDCBBBAAAAABCEEEEEEF",
      "FFEEDCBBBAAAAABCEEEEEEFF",
      "FEEDCBBBAAAAABCEEEEEEFFF",
      "EEDCBBBAAAAABCEFEEEEFFFF",
      "EDCBBBAAAAABCEFEEEEFFFFE",
      "DCBBBAAAAABCEFEEEEFFFFED",
      "CBBBAAAAABCEFEEEEFFFFEDD",
      "BBBAAAAABCEFEEEEFFFFEDDC",
      "BBAAAAABCEFEEEEFFFFEDDCB",
      "BAAAAABCEFEEEEFFFFEDDCBA",
      "AAAAABCEFEEEEFFFFEDDCBAB",
      "AAAABCEFEEEEFFFFEDDCBBBA",
      "AAABCEFEEEEFFFFEDDCBBBAA",
      "AABCEFEEEEFFFFEDDCBBBAAA",
      "ABCEFEEEEFFFFEDDCBBBAAAA",
      "BDEFEEEEFFFFEDDCBBBAAAAA",
      "DEFEEEEFFFFEDDCBBBAAAAAB",
      "EFEEEEFFFFEDDCBBBAAAAABB",
      "FEEEEFFFFEEDCCBBAAAAABBB",
      "EEEFFFFFEEDCCBBAAAAABBBC",
      "FEFFFFFEEDCCBCAAAAABBBCD",
      "FFFFFFFEDCCBCAAAAABBBDDD",
      "FFFFFFEDDCBCAAAAABBCDDDD",
      "FFFFFEEDCBCAAAAABBCDDDDD",
      "FFFFEEDCBCAAAAABBCDDDDDD",
      "FFFFEDCBCAAAAABBCDDDDDEE",
      "FFFEDCBCAAAAABBCDDDDDEEE",
      "FFEDCBCAAAAABBCEEEDEEEFF",
      "FFDDBCAAAAABBCEEEEEEEFFE",
      "FEDBCAAAAABBCEEEEEEEFFEE",
      "EDCCAAAAABBCEEEEEEFFFFED",
      "DCDAAAAABBCEEEEEFFFFFEDC",
      "CDAAAAABBCEEEEEFFFFFEDCB",
      "DAAAAABBCEEEEEFFFFFEDCBB",
      "AAAAABBCEEEEEFFFFFEDCBBC",
      "AAAABBCEEEEEFFFFFEDCBBCA",
      "AAABCCEEEEEFFFFFEDCBBCAA",
      "AABCCEEEEEFFFFFEDCCBCAAA",
      "ABCCEEEEEFFFFFEDCCBCAAAA",
      "BCCEEEEEFFFFFEDCCBCAAAAA",
      "CDEEEEEFFFFFEDCCBCAAAAAB",
      "DEEEEEFFFFFEDCCBCAAAAABB",
      "EEEEEFFFFFEDCCBCAAAAABBC",
      "EEEEFFFFFEDCCBCAAAAABBCD",
      "EEEFFFFFEDCCBCAAAAABBCDE",
      "EEFFFFFEDCCBCAAAAABBCDEE",
      "EFFFFFEDCCBCAAAAABBCDEEE",
      "FFFFFEDCCBCAAAAABBCDEEEE",
      "FFFFEDCCBCAAAAABBCDEEEEF",
      "FFFEDCCBCAAAAABBCEEEEEFF",
      "FFEDCCBCAAAAABBCEEEEEFFF",
      "FEDCCBCAAAAABBCDEEEEFFFF",
      "EDCCBCAAAAABBCDEEEEFFFFF",
      "DCCBCAAAAABBCDEEEEFFFFFF",
      "CCBCAAAAABBCDEEEEEFFFFFE",
      "CBCAAAAABBCDEEEEEFFFFFED",
      "BCAAAAABBCDEEEEEFFFFFEDC",
      "CAAAAABBCDEEEEEFFFFFEDCB",
      "AAAAABBCDEEEEEFFFFFEDCBC",
      "AAAABBBDEEEEEFFFFFEDCBCA",
      "AAABBBDEEEEEFFFFFEDCBCAA",
      "AABBBDEEEEEFFFFFEDCBCAAA",
      "AABBDEEEEFFFFFFEDCBCAAAA",
      "AABDEEEEFFFFFFEDCBCAAAAB",
      "ABDEEEEEFFFFFECCBCAAAAAD",
      "BDDEDEEEFFFEECBACAAAAADF",
      "CDDDDEEEFEEDCBABAAAAADFF",
      "DDDDDEEEEEDCBABAAAAADEFF",
      "DCDDDEEEDDCBABAAAAACEFFF",
      "CCDDEEEDDCBABAAAAACEFFFF",
      "CDDDEDDCBBABAAAAACEFFFFF",
      "DDDDDDCBBABAAAAACDFFFFFF",
      "CDDDDCBBABAAAAACDFFFFFFF",
      "DDDCCBBABAAAAACDEFFFFFFF",
      "DDCCBBABAAAAACDEFFFEFFFF",
      "CCCBBABAAAAABDEFEEEFFFFF",
      "CCBBABAAAAABDEFEEEEFFFFE",
      "CBBABAAAAABCEFEEEEFFFFEE",
      "BBABAAAAABCEFEEEEFFFFEED",
      "BABAAAAABCEFEEEEFFFFEEDC",
      "ABAAAAABCEEEEEEFFFFEEDCB",
      "BAAAAABCEEEEEEFFFFEEDCBB",
      "AAAAABCEEEEEEFFFFEEDCBBB",
      "AAAABCEFEEEEFFFFEEDCBBBA",
      "AAABCEFEEEEFFFFEEDCBABAA",
      "AABCEFEEEEFFFFEDDCBABAAA",
      "ABCEFEEEEFFFFEDDCBABAAAA",
      "BCEFEEEEFFFFEDDCBABAAAAA",
      "CEFEEEEFFFFEDDCBABAAAAAB",
      "EFEEEEFFFFEDDCBABAAAAABC",
      "FEEEEFFFFEDDCBABAAAAABCE",
      "EEEEFFFFEEDCBABAAAAABCEE",
      "EEEFFFFEEDCBABAAAAABCEEE",
      "EEFFFFEEDCBABAAAAABCEEEE",
      "EFFFFEEDCBABAAAAABCEEEEE",
      "FFFFEEDCBABAAAAABCEEEEEE",
      "FFFEEDCBABAAAAABCEEEEEEF",
      "FFEEDCBABAAAAABCEEEEEEFF",
      "FEEDCBABAAAAABCEEEEEEFFF",
      "EEDCBABAAAAABCEEEEEEFFFF",
      "EDCBABAAAAABCEEEEEEFFFFE",
      "DCBABAAAAABCEEEEEEFFFFED",
      "CBABAAAAABCEEEEEEFFFFEDD",
      "BABAAAAABCEEEEEEFFFFEDDC",
      "ABAAAAABCEEEEEEFFFFEDDCB",
      "BAAAAABCEEEEEEFFFFEDDCBA",
      "AAAAABCEEEEEEFFFFEDDCBAB",
      "AAAABCEEEEEEFFFFEDDCBABA",
      "AAABCEEEEEEFFFFEDDCBABAA",
      "AABCEEEEEEFFFFEDDCBABAAA",
      "ABCEEEEEEFFFFEDDCBABAAAA",
      "BCEEEEEEFFFFEDDCBABAAAAA",
      "CEEEEEEFFFFEDDCBABAAAAAB",
      "EEEEEEFFFFEDDCBABAAAAABC",
      "EEEEEFFFFEEDCBABAAAAABCE",
      "EEEEFFFFEEDCBABAAAAABCEE",
      "EEEFFFFEEDCBABAAAAABCEEE",
      "EEFFFFEEDCBABAAAAABCEEEE",
      "EFFFFEEDCBABAAAAABCEEEEE",
      "FFFFEEDCBABAAAAABCEEEEEE",
      "FFFEEDCBABAAAAABCEEEEEEF",
      "FFEEDCBABAAAAABCEEEEEEFF",
      "FEEDCBABAAAAABCEFEEEEFFF",
      "EEDCBABAAAAABCEFEEEEFFFF",
      "EDCBABAAAAABCEFEEEEFFFFE",
      "DCBABAAAAABCEFEEEEFFFFED",
      "CBABAAAAABCEFEEEEFFFFEDD",
      "BABAAAAABCEFEEEEFFFFEEDC",
      "ABAAAAABCEFEEEEFFFFEEDCB",
      "BAAAAABCEFEEEEFFFFEEDCBA",
      "AAAAABCEFEEEEFFFFEEDCBAB",
      "AAAABCEFEEEEFFFFEEDCBABA",
      "AAABCEFEEEEFFFFEEDCBABAA",
      "AABCEFEEEEFFFFEEDCBABAAA",
      "ABCEFEEEEFFFFEEDCBABAAAA",
      "BCEFEEEEFFFFEEDCBBBAAAAA",
      "CEFEEEEFFFFEEDCBBBAAAAAB",
      "EFEEEEFFFFEEDCBBBAAAAABC",
      "FEEEEFFFFEEDCBBBAAAAABCE",
      "EEEEFFFFEEDCBBBAAAAABCEE",
      "EEEFFFFEEDCBBBAAAAABCEEE",
      "EEFFFFEEDCBBBAAAAABCEEEE",
      "EFFFFEEDCBBBAAAAABCEEEEE",
      "FFFFEEDCBBBAAAAABCEEEEEE",
      "FFFEEDCBBBAAAAABCEEEEEEF",
      "FFEEDCBBBAAAAABCEEEEEEFF",
      "FEEDCBBBAAAAABCEEEEEEFFF",
      "EEDCBBBAAAAABCEEEEEEFFFF",
      "EDCBBBAAAAABCEEEEEEFFFFE",
      "DCBBBAAAAABCEEEEEEFFFFEE",
      "CBBBAAAAABCEFEEEEFFFFEED",
      "BBBAAAAABCEFEEEEFFFFEEDC",
      "BBAAAAABCEFEEEEFFFFEEDCB",
      "BAAAAABCEFEEEEFFFFEEDCBA"
    }
  }
}
```
--]]

require "circular_buffer"
require "math"
require "os"
require "sax"
require "string"
local alert = require "heka.alert"

local SAX_CARDINALITY   = 6
local SECS_IN_MINUTE    = 60
local HOURS_IN_DAY      = 24
local HOURS_IN_WEEK     = 168
local MINS_IN_DAY       = SECS_IN_MINUTE * HOURS_IN_DAY
local doc_type          = read_config("doc_type")
local sax_hours         = {}
local win               = sax.window.new(MINS_IN_DAY, HOURS_IN_DAY, SAX_CARDINALITY)

phour = 0
cb = circular_buffer.new(MINS_IN_DAY + 1, 1, SECS_IN_MINUTE)
cb:set_header(1, doc_type)

local function load_sax_hours()
    local a = alert.get_threshold(doc_type)
    assert(#a == HOURS_IN_WEEK, "invaild SAX alert threshold configuration")
    for i, v in ipairs(a) do
        assert(#v == HOURS_IN_DAY, "invalid SAX word")
        sax_hours[i] = sax.word.new(v, SAX_CARDINALITY)
    end
end
load_sax_hours()


function process_message()
    local ts = read_message("Timestamp")
    cb:add(ts, 1, 1)
    return 0
end


local alert_template = [[
SAX Analysis
============
start time: %s
end time  : %s
current   : %s
historical: %s
mindist   : %g

graph: %s
]]


function timer_event(ns, shutdown)
    local e = cb:current_time() - 60e9
    local s = e - ((MINS_IN_DAY - 1) * 60e9)
    local hour = math.floor(s / 3600e9 % HOURS_IN_WEEK) + 1
    if phour ~= hour then
        phour = hour
        win:add(cb:get_range(1, s, e))
        local mindist = sax.mindist(win, sax_hours[hour])
        local current = tostring(win)
        if mindist ~= 0 and not current:match("^#") then
            if alert.send(doc_type, "mindist",
                          string.format(alert_template,
                                        os.date("%Y%m%d %H%M%S", s / 1e9),
                                        os.date("%Y%m%d %H%M%S", e / 1e9),
                                        current,
                                        tostring(sax_hours[hour]),
                                        mindist,
                                        alert.get_dashboard_uri(doc_type))) then
                cb:annotate(ns, 1, "alert", string.format("mindist: %.4g", mindist))
            end
        end
    end
    inject_payload("cbuf", doc_type, cb)
end