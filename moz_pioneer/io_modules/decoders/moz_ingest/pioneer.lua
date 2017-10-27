-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Pioneer Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_ingest_pioneer = {
    -- JSON document representation conforming to JSON Web Key (JWK) IETF ID draft-ietf-jose-json-web-key
    _jose_keys = {
    ["pioneer-20170901"] = [=[
{
  "kty": "RSA",
  "e": "AQAB",
  "n": "vlbWUA9HUDHB5MDotmXObtE_Y4zKtGNtmPHUy_xkp_fSr0BxNdSOUzvzoAhK3sxTqpzVujKC245RHJ84Hhbl-KDj-n7Ee8EV3nKpnsqiBgHyc3rBpxpIi0J8kYmpiPGXu7k4xnCWCeiu_gfFGzvPdLHzlV7WOfYIHvymtbS7WOyTQLBgDjUKfHdJzH75vogy35h_mEcS-pde-EIi7u4OqD3bNW7iLbf2JVLtSNUYNCMMu23GsOEcBAsdf4QMq5gU-AEFK4Aib8mSPi_tXoohembr-JkzByRAkHbdzoGXssj0EHESt4reDfY8enVo5ACKmzbqlIJ1jmPVV6EKPBPzcQiN9dUA43xei2gmRAswdUKnexVPAPFPfKMpLqr24h1e7jHFBQL23-QqZX-gASbEDiYa9GusSY4kRn80hZRqCq4sgIRVEiu3ofjVdo4YzzESAkmfgFayUThhakqP82_wr9_Uc2vw3ZtlaTC_0LY70ne9yTy3SD3yEOa649nOTBfSh156YGtxvaHHidFojVHpPHBmjGAlak--mONHXHn00l_CVivUcuBqIGcZXRfiO6YwVDH_4ZTVzAkDov1C-4SNJK0XKeIwvGSspaSQrTmH_pT66L7tIhdZLTMVMh2ahnInVZP2G_-motugLq-x962JLQuLLeuh_r_Rk4VHZYhOgoc",
  "kid": "2940921e-3646-451c-8510-971552754e74",
  "d": "oMyvxXcC4icHDQBEGUOswEYabTmWTgrpnho_kg0p5BUjclbYzYdCreKqEPqwdcTcsfhJP0JI9r8mmy2PtSvXINKbhxXtXDdlCEaKMdIySyz97L06OLelrbB_mFxaU4z2iOsToeGff8OJgqaByF4hBw8HH5u9E75cYgFDvaJv29IRHMdkftwkfb4xJIfo6SQbBnbI5Ja22-lhnA4TgRKwY0XOmTeR8NnHIwUJ3UvZZMJvkTBOeUPT7T6OrxmZsqWKoXILMhLQBOyfldXbjNDZM5UbqSuTxmbD_MfO3xTwWWQXfIRqMZEpw1XRBguGj4g9kJ82Ujxcn-yLYbp08QhR0ijBY13HzFVMZ2jxqckrvp3uYgfJjcCN9QXZ6qlv40s_vJRRgv4wxdDc035eoymqGQby0UnDTmhijRV_-eAJQvdl3bv-R5dH9IzhxoJA8xAqZfVtlehPuGaXDAsa4pIWSg9hZkMdDEjW15g3zTQi3ba8_MfmnKuDe4GXYBjrH69z7epxbhnTmKQ-fZIxboA9sYuJHj6pEGT8D485QmrnmLjvqmQUzcxnpU6E3awksTp_HeBYLLbmrv4DPGNyVri2yPPTTRrNBtbWkuvEGVnMhvL2ed9uqLSnH8zOfgWqstqjxadxKADidYEZzmiYfEjYTDZGd9VDIUdKNGHWGFRB7UE",
  "p": "6VtjaNMD_VKTbs7sUQk-qjPTn6mCI8_3loqrOOy32b1G0HfIzCijuV-L7g7RxmMszEEfEILxRpJnOZRehN8etsIEuCdhU6VAdhBsBH5hIA9ZtX8GIs0sPrhc4kzPiwJ6JcLytUc6HCTICf2FIU7SI8I17-p53d35VItYiC1sGLZ2yN61VoKYNTncUSwboP2zXmGv4FPB5wQogryA_bEn-1U12FFSRd75Ku9GAEVxbTk3OaQqYgqfo9LnAWvunTDu31D4uyC6rze77NCo8UguqCpFjvF0ihOryQI6C3d0e8kxcM1vJbMvZNfrDN65btzqWi4m-CnqGYkl6BXQtS5UVw",
  "q": "0M7h_gtxoVoNPLRjYA5zBUD8qmyWiAzjloFOrDRLJwiD4OPHgImUx2WPTiSCjouvGqwfJh1jEEryJV_d0e4iVGyKYbFeXfzadwYXXR2jK4QwO1V_JDHI7HUYwNl6qzZqATi2zNKunPgIwY55gWBKjP2aUvPUBAcTeCsUPvrN_SajPVfc2wSlA2TvEnjmweNvgSTNqtBlMpmpwvEb9WXfv4pl3BfRvoTk3VR4icyvl-PLFedp2y0Fs0aQ4LRQ2ZMKWyGQEam_uAoa1tXrRJ_yQRvtWm1K8GpRZGKwN3TvtAg649PxQ7tJ8cvh3BwQROJyQBZDrlR04wqvDK4SNezlUQ"
}]=]
    },
    -- Filename of the telemetry schema use to wrap the pioneer data, since this
    -- is temporary hack for pioneer, dynamic lookup or telemetry subdecoders
    -- will not be implemented. Future implementations should use the generic
    -- moz_ingest pipeline.
    envelope_schema_file = "/usr/share/mozilla-pipeline-schemas/telemetry/pioneer-study/pioneer-study.4.schema.json",

    -- String used to specify the schema location on disk. The path should
    -- contain one directory for each docType and the files in the directory
    -- must be named <docType>.<version>.schema.json. If the schema file is not
    -- found for a docType/version combination, an error is thrown.
    schema_path = "/usr/share/mozilla-pipeline-schemas/pioneer-study",
}
```

## Functions

### transform_message

Transform and inject the message using the provided stream reader.

*Arguments*
- hsr (hsr) - stream reader with the message to process
- msg (table/nil) - optional message pre populated with metadata (i.e., geoCity)

*Return*
- throws on error

### decode

Decode and inject the message given as an argument, using a module-internal
stream reader.

*Arguments*
- msg (string) - Heka protobuf string to decode

*Return*
- throws on error
--]]

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")

local io     = require "io"
local lfs    = require "lfs"
local jose   = require "jose"
local rjson  = require "rjson"
local dt     = require "lpeg.date_time"
local mtn    = require "moz_telemetry.normalize"
local miu    = require "moz_ingest.util"

local assert               = assert
local error                = error
local pairs                = pairs
local pcall                = pcall
local type                 = type
local create_stream_reader = create_stream_reader
local read_config          = read_config
local inject_message       = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module


function load_json_schemas_dir(path)
    local schemas = {}
    for fn in lfs.dir(path) do
        local name = fn:match("(.+%.%d+)%.schema%.json$")
        if name then
            local fh = assert(io.input(string.format("%s/%s", path, fn)))
            local schema = fh:read("*a")
            fh:close()
            local ok, rjs = pcall(rjson.parse_schema, schema)
            if not ok then error(string.format("%s: %s", fn, rjs)) end
            schemas[name] = rjs
        end
    end
    return schemas
end


local function load_cfg()
    local cfg = read_config(module_cfg)
    assert(type(cfg) == "table", module_cfg .. " must be a table")

    assert(type(cfg.envelope_schema_file) == "string", "envelope_schema_file must be set")
    local fh = assert(io.input(cfg.envelope_schema_file))
    local schema = fh:read("*a")
    fh:close()
    local ok, envelope_schema = pcall(rjson.parse_schema, schema)
    if not ok then error(string.format("%s: %s", cfg.envelope_schema_file, envelope_schema)) end

    assert(type(cfg.schema_path) == "string", "schema_path must be set")
    local schemas = load_json_schemas_dir(cfg.schema_path)

    local cnt = 0
    local jose_keys = {}
    for k,v in pairs(cfg._jose_keys) do
        jose_keys[k] = jose.jwk_import(v)
        cnt = cnt + 1
    end
    assert(cnt > 0, "_jose_keys cannot be empty")
    return envelope_schema, schemas, jose_keys
end
local envelope_schema, schemas, jose_keys = load_cfg()

local submissionField = {value = nil, representation = "json"}
local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local function process_study(edata, jwk, schema)
    local ok, jwe = pcall(jose.jwe_import, edata)
    if not ok then
        error("jose\timport: " .. jwe, 0)
    end

    local ok, json = pcall(jwe.decrypt, jwe, jwk)
    if not ok then
        error("jose\tdecrypt: " .. json, 0)
    end

    local ok, err = pcall(doc.parse, doc, json)
    if not ok then
        error("json\tinvalid study: " .. err, 0)
    end

    ok, err = doc:validate(schema)
    if not ok then
        error("json\tstudy validation: " .. err, 0)
    end
    return doc
end


local env = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local function process_envelope(hsr)
    local ok, err = pcall(env.parse_message, env, hsr, "Fields[content]", nil, nil, true)
    if not ok then
        error("json\tinvalid envelope: " .. err, 0)
    end

    ok, err = env:validate(envelope_schema)
    if not ok then
        error("json\tenvelope validation: ".. err, 0)
    end
    return env
end


function transform_message(hsr, msg)
    if not msg then
        msg = miu.new_message(hsr)
    end

    local env = process_envelope(hsr)
    msg.Type = "telemetry"  -- make this look like telemetry ingestion

    -- populate the metadata so it is available to any error output
    local cts = env:value(env:find("creationDate"))
    if cts then
        msg.Fields.creationTimestamp = dt.time_to_ns(dt.rfc3339:match(cts))
    end
    msg.Fields.docType              = env:value(env:find("type"))
    local app = env:find("application")
    msg.Fields.appName              = env:value(env:find(app, "name"))
    msg.Fields.appVersion           = env:value(env:find(app, "version"))
    msg.Fields.appBuildId           = env:value(env:find(app, "buildId"))
    msg.Fields.appUpdateChannel     = env:value(env:find(app, "channel"))
    msg.Fields.appVendor            = env:value(env:find(app, "vendor"))
    msg.Fields.normalizedChannel    = mtn.channel(msg.Fields.appUpdateChannel)

    local pay = env:find("payload")
    msg.Fields.schemaName    = env:value(env:find(pay, "schemaName"))
    msg.Fields.schemaVersion = env:value(env:find(pay, "schemaVersion"))
    msg.Fields.studyName     = env:value(env:find(pay, "studyName"))
    msg.Fields.pioneerId     = env:value(env:find(pay, "pioneerId"))

    -- verify the decryption and validation metadata
    local ekey  = env:value(env:find(pay, "encryptionKeyId"))
    local jwk = jose_keys[ekey]
    if not jwk then
        error("jose\tno encryptionKeyId: " .. ekey, 0)
    end

    local sn = string.format("%s.%d", msg.Fields.schemaName, msg.Fields.schemaVersion)
    local schema = schemas[sn]
    if not schema then
        error(string.format("schema\tno schema: %s study: %s", sn, msg.Fields.studyName), 0)
    end

    -- decrypt and validate the study data
    local edata = env:value(env:find(pay, "encryptedData"))
    submissionField.value = process_study(edata, jwk, schema)
    msg.Fields.submission = submissionField

    local ok, err = pcall(inject_message, msg)
    msg.Fields.submission = nil
    if ok then
        -- inject a metadata only version for CEP debugging/monitoring
        msg.Type = "telemetry.metadata"
        pcall(inject_message, msg)
    else
        error("inject_message\t" .. err, 0)
    end
end


local hsr = create_stream_reader("decoders.moz_ingest.pioneer")
function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
