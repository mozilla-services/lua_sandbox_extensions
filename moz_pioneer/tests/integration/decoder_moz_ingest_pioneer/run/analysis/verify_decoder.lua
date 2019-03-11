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
        geoIP = "216.160.83.56",
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
        geoIP = "216.160.83.56",
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
        geoIP = "216.160.83.56",
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
        "encryptedData": "eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiUlNBLU9BRVAiLCAiemlwIjogIkRFRiIsICJraWQiOiAiMjk0MDkyMWUtMzY0Ni00NTFjLTg1MTAtOTcxNTUyNzU0ZTc0In0.N1n0JDBGFb8eiDM7CutG5MHfkpWgLtMBt3MXtAQFB5jX792vbJmvr0a3rUxLh3wOdff-xIV1sdmoV_svyVj-y043Jm3KxrHDzDGm9NoydsKbQJtsmDYgaAjoalmm7tQrp-0hYV5l39G7UIH1_mkNOTBO187aZ5JXc4hsDuULqVWc_pp7iGSSo_tTcoqWraimI1-pecMTJ8GCduLivjZY2miSnAY10fCkISp54xdZCAH9MNYk0yBAEwpjeO6Vk4epS10keRZEo4iZpxZWDhjCUdc0pdo-G40DXhLn6eK_NMd6U9k7KmkrknnxVaNN0QeHCBGPvFIiOcF6RVjI1vdAr5bbHklaEOIek2SdbpjylZLc0Fu0YJNZtxJJQnGKexci8i4agNVmfBKY-oojQWEDQcGPsp0WjQssL1dv71UfcUCjYfEbr4Rm_UMmi0j3xetLrSR_PArIiEOAkT357fzexlUnISkzXYI3DpBUFG-SL3nTUvm4_Xln4fpW0gte1T8ZF6Sf6_SrK7Jg2o6ZeQhg1GPkV5ePYmQqnVbIy7E7PnaeHkvK2KQRigCgXHXVsas7XDmpHyWtNIDVdQHY3vELD-eLSy3tRJhyEUA4mUliniobJqYrp9BHE2koQPXVMcRrBkQ7Eny8anlhIcY5HGKZDyUj2ZP0LyhRHrxV4lce0ho.ou76dtr-FiasUBSB.u15NVFawDnuxwFZs.CePzeSog14yBe5lB31dVrA",
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
        geoIP = "216.160.83.56",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "study validation: SchemaURI: #/properties/eventId Keyword: type DocumentURI: #/eventId",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "no encryptionKeyId: pioneer-20200901",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no schema: bogus.1 study: test-study",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no schema: event.2 study: test-study",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry", Fields = {
        schemaName = "shield-study",
        schemaVersion = 3,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        submission = {value = [[{"version":3,"study_name":"test-study","branch":"control","addon_version":"0.1.1","shield_version":"1.2.3","testing":true,"type":"shield-study","data":{"study_state":"ineligible"}}]], value_type = 1, representation = "json"},
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoIP = "216.160.83.56",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A07",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.metadata", Fields = {
        schemaName = "shield-study",
        schemaVersion = 3,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoIP = "216.160.83.56",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A07",
        geoCity = "Milton",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "invalid envelope: failed to parse offset:0 Invalid value.",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "envelope validation: SchemaURI: # Keyword: required DocumentURI: #",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "import: file: jwe.c line: 1205 function: cjose_jwe_import message: invalid argument",
        geoIP = "216.160.83.56"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "decrypt: file: jwe.c line: 894 function: _cjose_jwe_decrypt_dat_a256gcm message: crypto error",
        geoIP = "216.160.83.56"
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
