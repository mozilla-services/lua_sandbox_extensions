-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local oh = assert(io.open("import_releng.tsv", "w"))
local fh = assert(io.open("releng_table.tsv", "w"))

local mac      = 4.219666E-08
local moonshot = 5.07E-08
local bitbar   = 1.723187E-07

local phone_p  = "proj-autophone"
local bitbar_p = "bitbar"
local releng_p = "releng-hardware"

-- data source https://docs.google.com/spreadsheets/d/1X6NVk_m65A60tCumNseVCkEQiWd12g5Jywd52EJcONc/edit#gid=1391510946
data = {
{releng_p, "gecko-t-osx-1010", mac, 24},
{releng_p, "gecko-t-osx-1010-beta", mac, 2},
{releng_p, "gecko-t-osx-1014", mac, 400},
{releng_p, "gecko-t-osx-1014-beta", mac, 10},
{releng_p, "gecko-t-osx-1014-staging",mac, 8},

{releng_p, "gecko-t-linux-talos", moonshot, 186},
{releng_p, "gecko-t-linux-talos-b", moonshot, 8},
{releng_p, "gecko-t-win10-64-hb", moonshot, 4},
{releng_p, "gecko-t-win10-64-ht", moonshot, 6},
{releng_p, "gecko-t-win10-64-hw", moonshot, 396},
{releng_p, "gecko-t-win10-64-hw-dev", moonshot, 5},

{phone_p, "gecko-t-bitbar-gw-batt-g5", bitbar, 2},
{phone_p, "gecko-t-bitbar-gw-batt-p2", bitbar, 2},
{phone_p, "gecko-t-bitbar-gw-perf-g5", bitbar, 36},
{phone_p, "gecko-t-bitbar-gw-perf-p2", bitbar, 35},
{phone_p, "gecko-t-bitbar-gw-test-1", bitbar, 1},
{phone_p, "gecko-t-bitbar-gw-test-2", bitbar, 1},
{phone_p, "gecko-t-bitbar-gw-test-3", bitbar, 1},
{phone_p, "gecko-t-bitbar-gw-test-g5", bitbar, 1},
{phone_p, "gecko-t-bitbar-gw-unit-p2", bitbar, 21},
{releng_p, "gecko-t-win10-64-ref-18", bitbar, 2},
{releng_p, "gecko-t-win10-64-ref-ht", bitbar, 10},
{releng_p, "gecko-t-win10-64-ref-hw", bitbar, 16},
{bitbar_p, "gecko-t-win64-aarch64-laptop", bitbar, 34},
}


local function write_days(r)
    local time_t = 1561939200-- 2019-07-01 --1569888000 UTC -- 2019-10-01 UTC
    for i=1, 132 do
        local hours = 24 * r[4]
        local cost = hours * 3600 * 1000 * r[3]
        local provisioner = r[1]
        --if i < 42 then provisioner = "" end
        provisioner = ""
        oh:write(string.format("%s\t%s\t%s\t%g\t%g\t%g\n",os.date("%Y-%m-%d", time_t), provisioner, r[2], cost, hours, r[3]))
        time_t = time_t + 86400
    end
end

for i, r in ipairs(data) do
    write_days(r)
end

for i, r in ipairs(data) do
    fh:write(string.format("%s\t%s\t%g\t%d\n", r[1], r[2], r[3], r[4]))
end
