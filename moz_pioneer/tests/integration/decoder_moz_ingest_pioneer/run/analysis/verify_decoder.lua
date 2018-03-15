-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_ingest common/pioneer decoder
--]]

require "string"
local test = require "test_verify_message"

local messages = {
    {Logger = "telemetry", Type = "telemetry", Fields = {
        schemaName = "event",
        schemaVersion = 1,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        submission = {value = '{"eventId":"enrolled"}', value_type = 1, representation = "json"},
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.metadata", Fields = {
        schemaName = "event",
        schemaVersion = 1,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.duplicate", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "pioneer-study",
        geoCity = "Milton",
        geoCountry = "US",
        duplicateDelta = {value = 0, value_type = 2, representation = "1m"}
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        Host = "incoming.telemetry.mozilla.org",
        content = [[
{
      "id": "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
      "creationDate": "2015-11-05T01:25:43.312Z",
      "type": "pioneer-study",
      "version": 4,
      "application": {
        "architecture": "x86-64",
        "buildId": "20151103030248",
        "channel": "beta",
        "name": "Firefox",
        "platformVersion": "45.0",
        "vendor": "Mozilla",
        "version": "45.0",
        "displayVersion": "45.0b6",
        "xpcomAbi": "x86_64-gcc3"
      },
      "payload" : {
        "encryptedData": "eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiUlNBLU9BRVAiLCAiemlwIjogIkRFRiIsICJraWQiOiAiMjk0MDkyMWUtMzY0Ni00NTFjLTg1MTAtOTcxNTUyNzU0ZTc0In0.jR9EbyqYXQwNmPiZM9AZvWPM6Vv6ChjpLeq64O4Il7wQU5MUPHk90LTj6ELiyDseyl8OoslcXM3pjPzGy23Yum7-uI92vE-L0jVS5C6-UcAwdX7Z2ZMbUo0qcUIiNXupnCmUKUfRdWtFAU7TRt8u_8VulhvwYA1H9UEEkKQzPCpCVtDidzYellE-f4tp_GrL_PP2tuSI06-HRP5AyTItXxneDA5mqbgs9BfRVlWXJFqj76JdFMHwmvnOWhlffGy1HzqYoG1gqEPQIFOMZMmHLhyfEm6VCbVue-yxL93D1g-XXCCy1xCY43MF06d-rzWMhtzEAd7hoxfftBTt4u3LEL8GenBstiA4WacyNl7WOyf3b-8p6KnM7r0XzB-N5SZeg4dt3VWJmNb-0ZTP4pd5KCFUzSIyVq7CTewDh8Z4vlxPJOA4kqXpMKFdHLGf714me8QWfXlcMS6TCXNK0YYK7_FYEa-BmlgAtXO0AnmqRXH1sz4CBU4fXKDxwlslqQ7a4UYEBKsOcZkyWOY9Ppo4N-_aZ0s2iL3mH_6Ttpb40oM7hTb9qja36JAqpnWSf9PkxLke6lHqeoroOLYemn-3srfkRC-EVwWxS--LpanT5RsmP9k15XD6b1dK65-J3Y7ofvPjhoFY6kWapIjFvBw6wvYLjJJAjNFxb3Gu8PJ_4JU.5_H8dYZUyKLK5TZn.ZXwVWvDgKKyKw6gy.furesZOKHF8-YlTSWn-SlQ",
        "encryptionKeyId": "pioneer-20170901",
        "pioneerId": "11111111-1111-1111-1111-111111111111",
        "studyName": "test-study",
        "schemaName": "event",
        "schemaVersion": 1
      }
}
}]],
        DNT = "1",
        Date = "Wed, 30 Aug 2017 20:43:39 GMT",
        ["X-PingSender-Version"] = "1.0",
        uri = "/submit/telemetry/0055FAC4-8A1A-4FCA-B380-EBFDC8571A02/pioneer-study/Firefox/45.0/release/20151103030248",
        DecodeErrorType = "json",
        DecodeError = "invalid study: failed to parse offset:1 Invalid value.",
        schemaName = "event",
        schemaVersion = 1,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "study validation: SchemaURI: #/properties/eventId Keyword: type DocumentURI: #/eventId"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "no encryptionKeyId: pioneer-20200901"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no schema: bogus.1 study: test-study"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no schema: event.2 study: test-study"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "invalid envelope: failed to parse offset:0 Invalid value."
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "envelope validation: SchemaURI: # Keyword: required DocumentURI: #"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "import: file: jwe.c line: 1205 function: cjose_jwe_import message: invalid argument"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "decrypt: file: jwe.c line: 894 function: _cjose_jwe_decrypt_dat_a256gcm message: crypto error"
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
