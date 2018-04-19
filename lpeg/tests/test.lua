-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local files = {
    "common_log_format.lua",
    "date_time.lua",
    "escape_sequences.lua",
    "ip_address.lua",
    "logfmt.lua",
    "lpeg_heka.lua",
    "mysql.lua",
    "postfix.lua",
    "printf.lua",
}

for i,v in ipairs(files) do
    local f = assert(loadfile(v))
    f()
end
