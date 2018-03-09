-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

function process_message()
    return 0
end

local cnt = 0
function timer_event()
    cnt = cnt + 1
    if cnt == 6 then error"boom" end
end
