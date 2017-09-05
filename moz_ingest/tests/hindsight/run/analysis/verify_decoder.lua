-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_ingest common decoder
--]]

require "string"

local messages = {
    {Logger = "common", Type = "error", Hostname = "example.com", Fields = {
        docType = "foobar",
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "San Francisco",
        geoCountry = "US",
        sourceVersion = 1
        }
    },
    {Logger = "common", Type = "duplicate", Hostname = "integration_test", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        duplicateDelta = 0,
        geoCity = "San Francisco",
        geoCountry = "US",
        sourceVersion = 1
        }
    },
    {Logger = "common", Type = "error", Fields = {
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "Halifax",
        geoCountry = "CA",
        sourceVersion = 99
        }
    },
    {Logger = "common", Type = "error", Fields = {
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "New York",
        geoCountry = "US",
        sourceVersion = 99
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
