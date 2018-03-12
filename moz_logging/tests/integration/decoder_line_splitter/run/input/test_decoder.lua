-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local tests = {
    {[[
line one
line two
line three]], {Type = "default"}}
}

local dm = require("decoders.moz_logging.line_splitter").decode

function process_message()
    for i,v in ipairs(tests) do
        dm(unpack(v))
    end
    return 0
end
