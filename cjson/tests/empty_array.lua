-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cjson"

local ea = '[]'
local lea = {nil}

local eh = '{}'
local leh = {}

local sparse = "[1,2,null,4]"

function process()
    local t = cjson.decode(ea)
    local es = cjson.encode(t)
    assert(ea == es, es)

    es = cjson.encode(lea)
    assert(ea == es, es)

    t = cjson.decode(eh)
    es = cjson.encode(t)
    assert(eh == es, es)

    es = cjson.encode(leh)
    assert(eh == es, es)

    t = cjson.decode(sparse)
    es = cjson.encode(t)
    assert(sparse == es, es)
    return 0
end
