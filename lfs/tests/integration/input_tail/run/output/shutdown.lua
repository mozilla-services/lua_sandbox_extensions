-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "string"
local load_path = read_config("sandbox_load_path")

function process_message()
    local fn = string.format("%s/%s/%s.off", load_path,
                             string.match(read_message("Payload"), "([^.]+)%.(.*)"))
    local fh = assert(io.open(fn, "w+"))
    fh:close()
    return 0
end

function timer_event()
end
