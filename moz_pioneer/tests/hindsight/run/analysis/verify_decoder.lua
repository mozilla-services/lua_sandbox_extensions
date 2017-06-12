-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_pioneer JSOE decoder
--]]

require "string"

local messages = {
    {Type = "pioneer", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "heatmap",
        sourceVersion = 1,
        submission = '{"user":"abc1","sessions":[{"start_time":1496847280,"url":"http://some.website.com/and/the/url?query=string","tab_id":"-31-2","duration":2432},{"start_time":1496846280,"url":"https://foo.website.com/and/the/url#anchor","tab_id":"-2-14","duration":4410}]}'
        }
    },
    {Type = "pioneer", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        submission = '{"user":"abc2","sessions":[{"start_time":1496847280,"url":"http://some.website.com/and/the/url?query=string"}]}'
        }
    },
    {Type = "pioneer.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "heatmap schema version 1 validation error: SchemaURI: # Keyword: required DocumentURI: #"
        },
    },
    {Type = "pioneer.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "invalid submission: failed to parse offset:1 Invalid value."
        }
    },
    {Type = "pioneer.error", Fields = {
        DecodeErrorType = "jwe_import",
        DecodeError = "file: base64.c line: 111 function: _decode message: invalid argument"
        },
    },
    {Type = "pioneer.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no schema: bogus ver: 1"
        }
    },
    {Type = "pioneer.error", Fields = {
        DecodeErrorType = "uri",
        DecodeError = "invalid URI"
        }
    },
    {Type = "pioneer.duplicate", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        duplicateDelta = 0
        }
    }
}

local function verify_fields(idx, fields)
    for k,v in pairs(fields) do
        local name = string.format("Fields[%s]", k)
        local r = read_message(name)
        assert(v == r, string.format("Test %d Fields[%s] = %s", idx, k, tostring(r)))
    end
end

local function verify_message(idx)
    local msg = messages[idx]
    for k,v in pairs(msg) do
        if k == "Fields" then
            verify_fields(idx, v)
        else
            local r = read_message(k)
            assert(v == r, string.format("Test %d %s = %s", idx, k, tostring(r)))
        end
    end
end

local cnt = 0
function process_message()
    cnt = cnt + 1
    verify_message(cnt)
    return 0
end

function timer_event(ns)
    assert(cnt == 8, tostring(cnt) .. " of 8 tests ran")
end
