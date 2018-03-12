-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local tests = {
    {[[
{"Logger":"input1", "Items":[{}]}
{"Logger":"input2", "Type":"type2"}
{{invalid}
{"foo":"bar", "Timestamp":123456789, "bstring":{"value":"binary", "value_type":1}}
{"array":{"value":[1,2,3], "value_type":2, "representation":"count"}}]]
        , {Type = "default"}}
}

local dm = require("decoders.moz_logging.json_heka_fields").decode

function process_message()
    for i,v in ipairs(tests) do
        dm(unpack(v))
    end
    return 0
end
