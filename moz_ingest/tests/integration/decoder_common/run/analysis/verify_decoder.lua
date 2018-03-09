-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
local test = require "test_verify_message"

local messages = {
    {Logger = "moz_ingest", Type = "error", Hostname = "example.com", Fields = {
        DecodeErrorType = "uri",
        DecodeError = "missing uri",
        }
    },
    {Logger = "moz_ingest", Type = "error", Hostname = "example.com", Fields = {
        uri = "/foobar",
        DecodeErrorType = "uri",
        DecodeError = "invalid uri",
        }
    },
    {Logger = "common", Type = "error", Hostname = "example.com", Fields = {
        uri = "/submit/common/foobar/1/0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "foobar",
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "Milton",
        geoCountry = "US",
        docVersion = 1
        }
    },
    {Logger = "common", Type = "duplicate", Hostname = "integration_test", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "foobar",
        duplicateDelta = {value = 0, value_type = 2, representation = "1m"},
        geoCity = "Milton",
        geoCountry = "US",
        docVersion = 1
        }
    },
    {Logger = "common", Type = "error", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        uri = "/submit/common/widget/99/0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        docType = "widget",
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "Halifax",
        geoCountry = "CA",
        docVersion = 99
        }
    },
    {Logger = "common", Type = "error", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A03",
        uri = "/submit/common/widget/99/0055FAC4-8A1A-4FCA-B380-EBFDC8571A03",
        docType = "widget",
        DecodeErrorType = "skipped",
        DecodeError = "no sub decoder",
        geoCity = "Milton",
        geoCountry = "US",
        geoISP = "Century Link",
        docVersion = 99
        }
    },
}

local cnt = 0
function process_message()
    cnt = cnt + 1
    local received = decode_message(read_message("raw"))
    test.fields_array_to_hash(received)
    test.verify_msg(messages[cnt], received, cnt)
    return 0
end

function timer_event(ns)
    assert(cnt == #messages, string.format("%d of %d tests ran", cnt, #messages))
end
