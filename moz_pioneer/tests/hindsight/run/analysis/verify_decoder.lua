-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_ingest common/pioneer decoder
--]]

require "string"

local messages = {
    {Logger = "telemetry", Type = "telemetry", Fields = {
        studyVersion = 1,
        appVersion = "45.0",
        studyName = "example",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        submission = '{"exampleString":"foobar"}',
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        geoCity = "San Francisco",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.metadata", Fields = {
        studyVersion = 1,
        appVersion = "45.0",
        studyName = "example",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        geoCity = "San Francisco",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.duplicate", Fields = {
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A01",
        docType = "pioneer-study",
        geoCity = "San Francisco",
        geoCountry = "US",
        duplicateDelta = 0
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
        "encryptedData": "eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiUlNBLU9BRVAiLCAiemlwIjogIkRFRiIsICJraWQiOiAiMjk0MDkyMWUtMzY0Ni00NTFjLTg1MTAtOTcxNTUyNzU0ZTc0In0.hnXLQf6VoLkjhikf2jeNUtWlwXuCj8nKUjcrOpsWvpLpeDxOJKrxs5Iqm5myxV8UIOrHCGnowmUvvG4bu-KLdC-QzXTmMGovwE8_VxVFO6gCVmKlgLBDgcfjbKajy7JGtozomuSz-lhP5BIMzVfMF6XoVSKq2YDskzVTMGZdVnPvzFjYJpK8lEKxA_MVZF-NJ_JJKn6jtbo3y5SvuXPOKVu7JBCwvrb6VHEm0tMwhCzeH3YemUluOXTeoCMXnKx0bRJhEoeb8Bh-oNLSEYKVI1jFK-Bzc3VZ1cBMTQ_nKWorObgewdYFZsxM4bChT3dtKxpb_udG2KtaUxyxfAoZ2r0GvphSnC2lITHoHk49C54-VttMZcMyHHvFEXO_gnBsVOoP0Z2b3LXAyL6dhxg8doc4CWTj3oAA2MnzQl7ZoaiFZc4NYuav2MYpSomyGmXSLs9qHXYSMhpq3q-qSyPEm28x2iEb05HsK9e0jUyRcy1JimjaC5x4tBi4xNMRpRUNWrYkqLDsi5EneUTCmVEhKStNk6fHnqOTWoM5A_55KAxTQWknsSVaGWXQtk2O9dsDa6f7Rm3Zssb_bQVXc_EjHimXd02fSnv6rThZ2qa7-wDlKYD88vrmD358oxdwziVBpfU4DRjdMefdJybxKz_l8fwVtp7dZBNC8p469s_a2y8.ZmoNDzcRaVqrnwgO.2iyWrGdfGuAtp1Tv.9yVPdJMA63ZuNpmAKLPnTw",
        "encryptionKeyId": "pioneer-20170901",
        "pioneerId": "11111111-1111-1111-1111-111111111111",
        "studyName": "example",
        "studyVersion": 1
      }
}
}]],
        DNT = "1",
        Date = "Wed, 30 Aug 2017 20:43:39 GMT",
        ["X-PingSender-Version"] = "1.0",
        uri = "/submit/telemetry/0055FAC4-8A1A-4FCA-B380-EBFDC8571A02/pioneer-study/Firefox/45.0/release/20151103030248",
        DecodeErrorType = "json",
        DecodeError = "invalid study: failed to parse offset:1 Invalid value.",
        studyVersion = 1,
        appVersion = "45.0",
        studyName = "example",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        appUpdateChannel = "beta",
        normalizedChannel = "beta",
        creationTimestamp = 1.446686743312e+18,
        docType = "pioneer-study",
        appBuildId = "20151103030248",
        geoCountry = "US",
        appVendor = "Mozilla",
        documentId = "0055FAC4-8A1A-4FCA-B380-EBFDC8571A02",
        geoCity = "San Francisco",
        appName = "Firefox"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "json",
        DecodeError = "study validation: SchemaURI: #/properties/exampleString Keyword: type DocumentURI: #/exampleString"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "jose",
        DecodeError = "no encryptionKeyId: pioneer-20200901"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no study schema: bogus ver: 1"
        }
    },
    {Logger = "telemetry", Type = "telemetry.error", Fields = {
        DecodeErrorType = "schema",
        DecodeError = "no study schema: example ver: 2"
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
