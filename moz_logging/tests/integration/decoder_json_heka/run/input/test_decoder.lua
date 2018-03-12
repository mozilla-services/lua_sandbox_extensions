-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local tests = {
    {[[
{"Logger":"input1", "Fields":[{}]}
{"Logger":"input1"}
{"Logger":"input2", "Type":"type2"}
{"Logger":"input2", "Type":"type2", "Fields":{"agent":"Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:27.0) Gecko/20100101 Firefox/27.0"}}
{"Logger":"input2", "Type":"type2", "Fields":{"foo":"bar"}}
{{invalid}
{"foo":"bar", "Timestamp":123456789, "nested":{"level1":"l1"}, "deep":{"level1":{"level2":{"level3":{"level4":"value"}}}}}]]
        , {Type = "default"}}
}

local dm = require("decoders.moz_logging.json_heka").decode

function process_message()
    for i,v in ipairs(tests) do
        dm(unpack(v))
    end
    return 0
end
