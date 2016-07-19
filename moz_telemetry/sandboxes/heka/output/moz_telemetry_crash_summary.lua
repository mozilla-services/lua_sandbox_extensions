-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Crash Ping Summary Output

## Sample Configuration
```lua
filename = "moz_telemetry_crash_summary.lua"
message_matcher = "Type == 'telemetry' && Fields[docType] == 'crash'"

format      = "redshift.psv"
buffer_dir = "/mnt/output"
buffer_size = 20 * 1024 * 1024
s3_uri     = "s3://test"
```
--]]

local ds  = require "heka.derived_stream"
local mtn = require "moz_telemetry.normalize"
local mtp = require "moz_telemetry.ping"

local name = "crash_summary"
local schema = {
--  column name                 type            length  attributes  field /function
    {"Timestamp"                ,"TIMESTAMP"    ,nil    ,"SORTKEY"  ,"Timestamp"},
    {"crashDate"                ,"DATE"         ,nil    ,nil        ,function () return mtp.get_date(mtp.payload().payload.crashDate) end},
    {"clientId"                 ,"CHAR"         ,36     ,"DISTKEY"  ,"Fields[clientId]"},
    {"buildVersion"             ,"VARCHAR"      ,32     ,nil        ,function () return mtp.build().version end},
    {"buildId"                  ,"CHAR"         ,14     ,nil        ,function () return mtp.build().buildId end},
    {"buildArchitecture"        ,"VARCHAR"      ,32     ,nil        ,function () return mtp.build().architecture end},
    {"channel"                  ,"VARCHAR"      ,7      ,nil        ,function () return mtn.channel(read_message("Fields[appUpdateChannel]")) end},
    {"os"                       ,"VARCHAR"      ,7      ,nil        ,function () return mtn.os(read_message("Fields[os]")) end},
    {"osVersion"                ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.version end},
    {"osServicepackMajor"       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.servicePackMajor end},
    {"osServicepackMinor"       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.servicePackMinor end},
    {"locale"                   ,"VARCHAR"      ,32     ,nil        ,function () return mtp.settings().locale end},
    {"activeExperimentId"       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.addons().activeExperiment.id end},
    {"activeExperimentBranch"   ,"VARCHAR"      ,32     ,nil        ,function () return mtp.addons().activeExperiment.branch end},
    {"country"                  ,"VARCHAR"      ,5      ,nil        ,function () return mtn.country(read_message("Fields[geoCountry]")) end},
    {"hasCrashEnvironment"      ,"BOOLEAN"      ,nil    ,nil        ,function () return mtp.payload().payload.hasCrashEnvironment end},
}

local ds_pm
ds_pm, timer_event = ds.load_schema(name, schema)

function process_message()
    mtp.clear_cache()
    return ds_pm()
end

