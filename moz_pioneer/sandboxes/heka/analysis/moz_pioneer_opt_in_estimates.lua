-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Pioneer Opt-in Enrollment

Plugin that estimates the number of users who have the Pioneer Opt-in
add-on installed per-day.

See: https://bugzilla.mozilla.org/show_bug.cgi?id=1447331

https://docs.telemetry.mozilla.org/concepts/data_pipeline.html#hindsight

## Sample Configuration

```lua
filename = 'moz_pioneer_opt_in_estimates.lua'
message_matcher = 'Type=="telemetry" && Fields[docType]=="main" && Fields[environment.addons] =~ "pioneer-opt-in@mozilla.org"%'
preserve_data = true
ticker_interval = 60
```

## Sample Output
Keys are the date in `YEARMONTHDAY` format, values are the estimated number of
users who sent a ping that included the Pioneer add-on that day.
```json
{
  "20171001": 4523,
  "20171002": 5937,
  "20171003": 3002
}
```
--]]
require "cjson"
require "hyperloglog"

pioneer_day_hlls = {}

function process_message()
    local day = read_message("Fields[submissionDate]")
    local hll = pioneer_day_hlls[day]
    if not hll then
      hll = hyperloglog.new()
      pioneer_day_hlls[day] = hll
    end
    hll:add(read_message("Fields[clientId]"))
    return 0
end


function timer_event()
    local pioneer_day_counts = {}
    local count = 0
    local earliest_day = nil
    for day, hll in pairs(pioneer_day_hlls) do
      pioneer_day_counts[day] = hll:count()
      count = count + 1
      if not earliest_day or day < earliest_day then
        earliest_day = day
      end
    end
    inject_payload("json", "pioneer_opt_in_count", cjson.encode(pioneer_day_counts))
    if count > 30 then
      pioneer_day_hlls[earliest_day] = nil
    end
end
