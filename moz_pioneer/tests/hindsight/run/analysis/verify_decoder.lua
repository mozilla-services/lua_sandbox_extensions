-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for moz_ingest common/pioneer decoder
--]]

require "string"

local messages = {
    {Logger = "telemetry", Type = "telemetry", Fields = {
        schemaName = "event",
        schemaVersion = 1,
        appVersion = "45.0",
        studyName = "test-study",
        pioneerId = "11111111-1111-1111-1111-111111111111",
        submission = '{"eventId":"enrolled"}',
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
        "encryptedData": "eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiUlNBLU9BRVAiLCAiemlwIjogIkRFRiIsICJraWQiOiAiMjk0MDkyMWUtMzY0Ni00NTFjLTg1MTAtOTcxNTUyNzU0ZTc0In0.ds7LT3vtshHRibx3twJQSKb8n_W6EtvpD7597KjMBsA4NySKTF0cgGE4m7MvMDXzYUeJq5K1sAnuYNAFdUML2my06rXWB3Q8gP6PRjF2hYzj84NKYVBwBr0XdgSfGqx_ja3XZX0f8LKkCUppRDo_9YuK-7kkw4_NDMLen-f3o9ta87w9Nn9lbw1m62yhkR8S2jiK3W4jpCnbxIeyZMyo-u-iCdEN4gdtH3ledcpeSZXn6b-L6d_4iQx2Y98Y5xvkSakXkipowsDd9FI7yE_gprV1pJDV29lDmH7Km_9ZSGA6NQTZs0fkOcJIhZprW4Bq_aP2tlPBU343dC-6lrVitQLxGgYgUDZduR4E0T3XJ4LJaPNIJKsTx-s9UXGur0U0qCIBT-bJKD3bBeVJmSA7ZMcuOGHktCQsx0Fr84IOInFaOCZSulPS_H0IThB23Z-Z9e-dX-c1s-YfjSUvMiyuG_mciDLo27AsN2FMOPQD-tKkOgnz231Ri3GTK777OYpsYTr8Q0vBRdVLJIi_-dIMTSuRHX3RCwduVpR_EnPdvMh_O7949W45gLoyz_Z96BarU6WDssPrCLGPkHHVDQqCO7nHz8RB5l5Jpq0Y2D_2Aaq14qDZBfldgkZJC6QufefoVtwqWWdd_R_PE_gqazJmGTsesHtgTnvT8VydnmxeyIo.LM9z4RRfWVynWd0u.SQehWUthukk7EUX2.L8zyxPzzWbDalhMdLlCPhg",
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
        geoCity = "San Francisco",
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
