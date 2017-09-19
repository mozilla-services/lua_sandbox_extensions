-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_ingest common decoder
--]]

require "string"

local messages = {
    {Logger = "foo", Type = "validated", Hostname = "example.com", Fields = {
        docVersion = 1,
        docType = "bar",
        geoCity = "New York",
        geoCountry = "US",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01"
        }
    },
    {Logger = "foo", Type = "error", Hostname = "example.com", Fields = {
        uri = "/submit/foo/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        docType = "bar",
        DecodeErrorType = "json",
        DecodeError = "invalid submission: failed to parse offset:0 Invalid value.",
        geoCity = "New York",
        geoCountry = "US",
        docVersion = 1,
        content = ""
        }
    },
    {Logger = "foo", Type = "error", Hostname = "example.com", Fields = {
        uri = "/submit/foo/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A03",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A03",
        docType = "bar",
        DecodeErrorType = "json",
        DecodeError = "namespace: foo schema: bar version: 1 error: SchemaURI: # Keyword: required DocumentURI: #",
        geoCity = "New York",
        geoCountry = "US",
        docVersion = 1,
        content = [[{"xString":"string one"}]]
        }
    },
    {Logger = "bar", Type = "error", Hostname = "example.com", Fields = {
        uri = "/submit/bar/bar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "bar",
        DecodeErrorType = "json",
        DecodeError = "namespace: bar schema: bar version: 1 error: schema not found",
        geoCity = "New York",
        geoCountry = "US",
        docVersion = 1,
        content = "{}"
        }
    },
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
    assert(cnt == #messages, string.format("%d of %d tests ran", cnt, #messages))
end
