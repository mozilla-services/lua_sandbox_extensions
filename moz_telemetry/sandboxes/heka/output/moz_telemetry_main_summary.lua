-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.


--[[
# Mozilla Telemetry Main Ping Summary Output

## Sample Configuration
```lua
filename = "moz_telemetry_main_summary.lua"
message_matcher = "Type == 'telemetry' && Fields[docType] == 'main'"

format      = "redshift.psv"
buffer_dir = "/mnt/output"
buffer_size = 100 * 1024 * 1024
s3_uri     = "s3://test"
```
--]]

local ds  = require "heka.derived_stream"
local mtn = require "moz_telemetry.normalize"
local mtp = require "moz_telemetry.ping"

local name = "main_summary"
local schema = {
--  column name                     type            length  attributes  field /function
    {"Timestamp"                    ,"TIMESTAMP"    ,nil    ,"SORTKEY"  ,"Timestamp"},
    {"subsessionDate"               ,"DATE"         ,nil    ,nil        ,function () return mtp.get_date(mtp.info().subsessionStartDate) end},
    {"clientId"                     ,"CHAR"         ,36     ,"DISTKEY"  ,"Fields[clientId]"},
    {"buildVersion"                 ,"VARCHAR"      ,32     ,nil        ,function () return mtp.build().version end},
    {"buildId"                      ,"CHAR"         ,14     ,nil        ,function () return mtp.build().buildId end},
    {"buildArchitecture"            ,"VARCHAR"      ,32     ,nil        ,function () return mtp.build().architecture end},
    {"channel"                      ,"VARCHAR"      ,7      ,nil        ,function () return mtn.channel(read_message("Fields[appUpdateChannel]")) end},
    {"os"                           ,"VARCHAR"      ,7      ,nil        ,function () return mtn.os(read_message("Fields[os]")) end},
    {"osVersion"                    ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.version end},
    {"osServicepackMajor"           ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.servicePackMajor end},
    {"osServicepackMinor"           ,"VARCHAR"      ,32     ,nil        ,function () return mtp.system().os.servicePackMinor end},
    {"locale"                       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.settings().locale end},
    {"activeExperimentId"           ,"VARCHAR"      ,32     ,nil        ,function () return mtp.addons().activeExperiment.id end},
    {"activeExperimentBranch"       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.addons().activeExperiment.branch end},
    {"country"                      ,"VARCHAR"      ,5      ,nil        ,function () return mtn.country(read_message("Fields[geoCountry]")) end},
    {"reason"                       ,"VARCHAR"      ,32     ,nil        ,function () return mtp.info().reason end},
    {"subsessionLength"             ,"INTEGER"      ,nil    ,nil        ,function () return mtp.info().subsessionLength end},
    {"timezoneOffset"               ,"INTEGER"      ,nil    ,nil        ,function () return mtp.info().timezoneOffset end},
    {"pluginHangs"                  ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_CRASHES_WITH_DUMP", "pluginhang") end},
    {"abortsPlugin"                 ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_ABNORMAL_ABORT", "plugin") end},
    {"abortsContent"                ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_ABNORMAL_ABORT", "content") end},
    {"abortsGmplugin"               ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_ABNORMAL_ABORT", "gmplugin") end},
    {"crashesdetectedPlugin"        ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_CRASHES_WITH_DUMP", "plugin") end},
    {"crashesdetectedContent"       ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_CRASHES_WITH_DUMP", "content") end},
    {"crashesdetectedGmplugin"      ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("SUBPROCESS_CRASHES_WITH_DUMP", "gmplugin") end},
    {"crashSubmitAttemptMain"       ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_ATTEMPT", "main-crash") end},
    {"crashSubmitAttemptContent"    ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_ATTEMPT", "content-crash") end},
    {"crashSubmitAttemptPlugin"     ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_ATTEMPT", "plugin-crash") end},
    {"crashSubmitSuccessMain"       ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_SUCCESS", "main-crash") end},
    {"crashSubmitSuccessContent"    ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_SUCCESS", "content-crash") end},
    {"crashSubmitSuccessPlugin"     ,"INTEGER"      ,nil    ,nil        ,function () return mtp.khist_sum("PROCESS_CRASH_SUBMIT_SUCCESS", "plugin-crash") end},
    {"activeAddons"                 ,"INTEGER"      ,nil    ,nil        ,function () return mtp.num_active_addons() end},
    {"flashVersion"                 ,"VARCHAR"      ,16     ,nil        ,function () return mtp.flash_version() end},
}

local ds_pm
ds_pm, timer_event = ds.load_schema(name, schema)

function process_message()
    mtp.clear_cache()
    return ds_pm()
end

