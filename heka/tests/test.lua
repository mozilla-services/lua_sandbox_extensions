-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local string = require "string"
local util = require "heka.util"

local t = {toplevel=0, struct = { item0 = 0, item1 = 1, item2 = {nested = "n1"}}}
local fa = {}
local fb = {}
local fc = {}

local function table_to_fields()
    util.table_to_fields(t, fa, nil)
    assert(fa.toplevel == 0, fa.toplevel)
    assert(fa["struct.item0"] == 0, fa["struct.item0"])
    assert(fa["struct.item1"] == 1, fa["struct.item1"])
    assert(fa["struct.item2.nested"] == "n1", fa["struct.item2.nested"])
    util.table_to_fields(t, fb, nil, "_", 2)
    assert(fb.toplevel == 0, fb.toplevel)
    assert(fb["struct_item0"] == 0, fb["struct_item0"])
    assert(fb["struct_item1"] == 1, fb["struct_item1"])
    assert(fb["struct_item2"] == '{"nested":"n1"}', fb["struct_item2"])
    util.table_to_fields(t, fc, nil, nil, 2)
    assert(fc.toplevel == 0, fc.toplevel)
    assert(fc["struct.item0"] == 0, fc["struct.item0"])
    assert(fc["struct.item1"] == 1, fc["struct.item1"])
    assert(fc["struct.item2"] == '{"nested":"n1"}', fc["struct.item2"])
end

table_to_fields()


local function table_to_message()

    local function verify_table(idx, t, expected)
        for k,v in pairs(expected) do
            local r = t[k]
            if type(v) == "table" then
                verify_table(idx, r, v)
            else
                assert(v == r, string.format("Test %d %s = %s", idx, k, tostring(r)))
            end
        end
    end

    local tests = {
        {{time = 1234}, {Timestamp = 1234}},
        {{host = "hname"}, {Hostname = "hname"}},
        {{app = "sshd"}, {Fields = {Program = "sshd"}}},
        {{ok = 1}, {Fields = {ok = true}}},
        {{len = 321}, {Fields = {len = {value = 321, value_type = 2}}}},
        {{avg = "3.34"}, {Fields = {avg = 3.34}}},
        {{version = 12.34}, {Fields = {version = "12.34"}}},
        {{data = "foo"}, {Fields = {data = {value = "foo", value_type = 1}}}},
        {{value = 123}, {Fields = {rename = {value = 123, value_type = 2}}}},
        {
            {
                Payload = "text",
                len = 321,
                other = "top",
                foo = {
                    bar = {
                        widget = "nested",
                        notmapped = "data"
                    }
                }
            },
            {
                Payload = "text",
                Fields = {
                    widget = "nested",
                    ["foo.bar.notmapped"] = "data",
                    other = "top",
                    len = {value = 321, value_type = 2, representation = "inches"}
                    }
            }
        },
        {{[1] = 456}, {Fields = {first = {value = 456, value_type = 2}}}},
    }

    local tmap = {
        time = {header = "Timestamp"},
        host = {header = "Hostname"},
        app  = {field  = "Program"},
        ok   = {field = "ok", type = "boolean"},
        len  = {field = "len", type = "int", representation = "inches"},
        avg  = {field = "avg", type = "double"},
        version = {field = "version", type = "string"},
        data = {field = "data", type = "bytes"},
        value = {field = "rename", type = "int"},
        foo = {
          bar = {
            widget = {field = "widget"}
          }
        },
        [1] = {field = "first", type = "int"},
    }

    for i,v in ipairs(tests) do
        local msg = util.table_to_message(v[1], tmap)
        verify_table(i, msg, v[2])
    end

    -- test empty map
    local msg = util.table_to_message(tests[10][1])
    verify_table(999, msg,
    {
        Payload = "text",
        Fields = {
            foo = '{"bar":{"widget":"nested","notmapped":"data"}}',
            other = "top",
            len = 321
            }
    })

end

table_to_message()
