-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Pioneer JOSE Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_pioneer_jose = {
    -- JSON document representation conforming to JSON Web Key (JWK) IETF ID draft-ietf-jose-json-web-key
    jose_jwk = [=[
{
  "kty": "RSA",
  "e": "AQAB",
  "n": "vlbWUA9HUDHB5MDotmXObtE_Y4zKtGNtmPHUy_xkp_fSr0BxNdSOUzvzoAhK3sxTqpzVujKC245RHJ84Hhbl-KDj-n7Ee8EV3nKpnsqiBgHyc3rBpxpIi0J8kYmpiPGXu7k4xnCWCeiu_gfFGzvPdLHzlV7WOfYIHvymtbS7WOyTQLBgDjUKfHdJzH75vogy35h_mEcS-pde-EIi7u4OqD3bNW7iLbf2JVLtSNUYNCMMu23GsOEcBAsdf4QMq5gU-AEFK4Aib8mSPi_tXoohembr-JkzByRAkHbdzoGXssj0EHESt4reDfY8enVo5ACKmzbqlIJ1jmPVV6EKPBPzcQiN9dUA43xei2gmRAswdUKnexVPAPFPfKMpLqr24h1e7jHFBQL23-QqZX-gASbEDiYa9GusSY4kRn80hZRqCq4sgIRVEiu3ofjVdo4YzzESAkmfgFayUThhakqP82_wr9_Uc2vw3ZtlaTC_0LY70ne9yTy3SD3yEOa649nOTBfSh156YGtxvaHHidFojVHpPHBmjGAlak--mONHXHn00l_CVivUcuBqIGcZXRfiO6YwVDH_4ZTVzAkDov1C-4SNJK0XKeIwvGSspaSQrTmH_pT66L7tIhdZLTMVMh2ahnInVZP2G_-motugLq-x962JLQuLLeuh_r_Rk4VHZYhOgoc",
  "kid": "2940921e-3646-451c-8510-971552754e74",
  "d": "oMyvxXcC4icHDQBEGUOswEYabTmWTgrpnho_kg0p5BUjclbYzYdCreKqEPqwdcTcsfhJP0JI9r8mmy2PtSvXINKbhxXtXDdlCEaKMdIySyz97L06OLelrbB_mFxaU4z2iOsToeGff8OJgqaByF4hBw8HH5u9E75cYgFDvaJv29IRHMdkftwkfb4xJIfo6SQbBnbI5Ja22-lhnA4TgRKwY0XOmTeR8NnHIwUJ3UvZZMJvkTBOeUPT7T6OrxmZsqWKoXILMhLQBOyfldXbjNDZM5UbqSuTxmbD_MfO3xTwWWQXfIRqMZEpw1XRBguGj4g9kJ82Ujxcn-yLYbp08QhR0ijBY13HzFVMZ2jxqckrvp3uYgfJjcCN9QXZ6qlv40s_vJRRgv4wxdDc035eoymqGQby0UnDTmhijRV_-eAJQvdl3bv-R5dH9IzhxoJA8xAqZfVtlehPuGaXDAsa4pIWSg9hZkMdDEjW15g3zTQi3ba8_MfmnKuDe4GXYBjrH69z7epxbhnTmKQ-fZIxboA9sYuJHj6pEGT8D485QmrnmLjvqmQUzcxnpU6E3awksTp_HeBYLLbmrv4DPGNyVri2yPPTTRrNBtbWkuvEGVnMhvL2ed9uqLSnH8zOfgWqstqjxadxKADidYEZzmiYfEjYTDZGd9VDIUdKNGHWGFRB7UE",
  "p": "6VtjaNMD_VKTbs7sUQk-qjPTn6mCI8_3loqrOOy32b1G0HfIzCijuV-L7g7RxmMszEEfEILxRpJnOZRehN8etsIEuCdhU6VAdhBsBH5hIA9ZtX8GIs0sPrhc4kzPiwJ6JcLytUc6HCTICf2FIU7SI8I17-p53d35VItYiC1sGLZ2yN61VoKYNTncUSwboP2zXmGv4FPB5wQogryA_bEn-1U12FFSRd75Ku9GAEVxbTk3OaQqYgqfo9LnAWvunTDu31D4uyC6rze77NCo8UguqCpFjvF0ihOryQI6C3d0e8kxcM1vJbMvZNfrDN65btzqWi4m-CnqGYkl6BXQtS5UVw",
  "q": "0M7h_gtxoVoNPLRjYA5zBUD8qmyWiAzjloFOrDRLJwiD4OPHgImUx2WPTiSCjouvGqwfJh1jEEryJV_d0e4iVGyKYbFeXfzadwYXXR2jK4QwO1V_JDHI7HUYwNl6qzZqATi2zNKunPgIwY55gWBKjP2aUvPUBAcTeCsUPvrN_SajPVfc2wSlA2TvEnjmweNvgSTNqtBlMpmpwvEb9WXfv4pl3BfRvoTk3VR4icyvl-PLFedp2y0Fs0aQ4LRQ2ZMKWyGQEam_uAoa1tXrRJ_yQRvtWm1K8GpRZGKwN3TvtAg649PxQ7tJ8cvh3BwQROJyQBZDrlR04wqvDK4SNezlUQ"
}]=],

    -- String used to specify the schema location on disk. The path should
    -- contain one directory for each docType and the files in the directory
    -- must be named <docType>.<version>.schema.json. If the schema file is not
    -- found for a docType/version combination, the default schema is used to
    -- verify the document is a valid json object.
    -- e.g., main/main.4.schema.json
    schema_path = "/mnt/work/mozilla-pipeline-schemas/schemas/pioneer",

    -- String used to specify GeoIP city database location on disk.
    city_db_file = "/mnt/work/geoip/city.db", -- optional, if not specified no geoip lookup is performed

    -- number of items in the de-duping cuckoo filter
    cf_items = 30e6, -- optional, if not provided de-duping is disabled

    -- interval size in minutes for cuckoo filter pruning
    cf_interval_size = 6, -- optional, default 1
}
```

## Functions

### transform_message

Transform and inject the message using the provided stream reader.

*Arguments*
- hsr (hsr) - stream reader with the message to process

*Return*
- none, injects an error message on decode failure

### decode

Decode and inject the message given as argument, using a module-internal stream reader.

*Arguments*
- msg (string) - binary message to decode

*Return*
- none, injects an error message on decode failure
--]]

-- Imports
local module_name   = ...
local string        = require "string"
local table         = require "table"
local module_cfg    = string.gsub(module_name, "%.", "_")

local jose   = require "jose"
local rjson  = require "rjson"
local io     = require "io"
local lfs    = require "lfs"
local l      = require "lpeg"
l.locale(l)
local table  = require "table"
local os     = require "os"
local floor  = require "math".floor

local read_config          = read_config
local assert               = assert
local error                = error
local pairs                = pairs
local create_stream_reader = create_stream_reader
local decode_message       = decode_message
local inject_message       = inject_message
local tonumber             = tonumber
local tostring             = tostring
local pcall                = pcall
local geoip
local city_db
local dedupe
local duplicateDelta
local jwk

-- create before the environment is locked down since it conditionally includes a module
local function load_decoder_cfg()
    local cfg = read_config(module_cfg)
    assert(type(cfg) == "table", module_cfg .. " must be a table")
    assert(type(cfg.schema_path) == "string", "schema_path must be set")
    jwk = jose.jwk_import(cfg.jose_jwk)
    if cfg.cf_items then
        if not cf_interval_size then cfg.cf_interval_size = 1 end
        local cfe = require "cuckoo_filter_expire"
        dedupe = cfe.new(cfg.cf_items, cfg.cf_interval_size)
        duplicateDelta = {value_type = 2, value = 0, representation = tostring(cfg.cf_interval_size) .. "m"}
    end

    if cfg.city_db_file then
        geoip = require "geoip.city"
        city_db = assert(geoip.open(cfg.city_db_file))
    end

    return cfg
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local cfg = load_decoder_cfg()
local UNK_GEO = "??"
-- Track the hour to facilitate reopening city_db hourly.
local hour = floor(os.time() / 3600)


local function get_geo_field(xff, remote_addr, field_name, default_value)
    local geo
    if xff then
        local first_addr = string.match(xff, "([^, ]+)")
        if first_addr then
            geo = city_db:query_by_addr(first_addr, field_name)
        end
    end
    if geo then return geo end
    if remote_addr then
        geo = city_db:query_by_addr(remote_addr, field_name)
    end
    return geo or default_value
end


local function get_geo_country(xff, remote_addr)
    return get_geo_field(xff, remote_addr, "country_code", UNK_GEO)
end


local function get_geo_city(xff, remote_addr)
    return get_geo_field(xff, remote_addr, "city", UNK_GEO)
end


local schemas = {}
local function load_schemas()
    for dn in lfs.dir(cfg.schema_path) do
        local fqdn = string.format("%s/%s", cfg.schema_path, dn)
        local mode = lfs.attributes(fqdn, "mode")
        if mode == "directory" and not dn:match("^%.") then
            for fn in lfs.dir(fqdn) do
                local name, version = fn:match("(.+)%.(%d+).schema%.json$")
                if name then
                    local fh = assert(io.input(string.format("%s/%s", fqdn, fn)))
                    local schema = fh:read("*a")
                    local s = schemas[name]
                    if not s then
                        s = {}
                        schemas[name] = s
                    end
                    local ok, rjs = pcall(rjson.parse_schema, schema)
                    if not ok then error(string.format("%s: %s", fn, rjs)) end
                    s[tonumber(version)] = rjs
                end
            end
        end
    end
end
load_schemas()


--[[
Read the raw message, annotate it with our error information, and attempt to inject it.
--]]
local function inject_error(hsr, err_type, err_msg, extra_fields)
    local len
    local raw = hsr:read_message("raw")
    local err = decode_message(raw)
    err.Logger = nil
    err.Type = "pioneer.error"
    if not err.Fields then
        err.Fields = {}
    else
        len = #err.Fields
        for i = len, 1, -1  do
            local name = err.Fields[i].name
            if name == "X-Forwarded-For" or name == "remote_addr" then
                table.remove(err.Fields, i)
            end
        end
    end
    len = #err.Fields
    len = len + 1
    err.Fields[len] = { name="DecodeErrorType", value=err_type }
    len = len + 1
    err.Fields[len] = { name="DecodeError",     value=err_msg }

    if extra_fields then
        -- Add these optional fields to the raw message.
        for k,v in pairs(extra_fields) do
            len = len + 1
            err.Fields[len] = { name=k, value=v }
        end
    end
    pcall(inject_message, err)
end


local submissionField = {value = nil, representation = "json"}
local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local function process_json(hsr, msg, schema)
    local ok, jwe = pcall(jose.jwe_import, hsr:read_message("Fields[content]"))
    if not ok then
        inject_error(hsr, "jwe_import", jwe, msg.Fields)
        return false
    end

    local ok, json = pcall(jwe.decrypt, jwe, jwk)
    if not ok then
        inject_error(hsr, "jwe_decrypt", json, msg.Fields)
        return false
    end

    local ok, err = pcall(doc.parse, doc, json)
    if not ok then
        inject_error(hsr, "json", string.format("invalid submission: %s", err), msg.Fields)
        return false
    end

    ok, err = doc:validate(schema)
    if not ok then
        inject_error(hsr, "json", string.format("%s schema version %d validation error: %s", msg.Fields.docType, msg.Fields.sourceVersion, err), msg.Fields)
        return false
    end

    submissionField.value = doc
    msg.Fields.submission = submissionField
    return true
end


local did = l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit
  * "-" * l.xdigit * l.xdigit * l.xdigit * l.xdigit
  * "-" * l.xdigit * l.xdigit * l.xdigit * l.xdigit
  * "-" * l.xdigit * l.xdigit * l.xdigit * l.xdigit
  * "-" * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit * l.xdigit

local split_uri = l.P"/submit/pioneer/"
  * l.C((l.P(1) - '/')^1) * '/'
  * (l.digit^1 / tonumber) * '/'
  * l.C(did) * -1

local function process_message(hsr)
    -- Path should be of the form: ^/submit/pioneer/heatmap/1/1ACA790F-76A3-4A48-AA16-B8C5ABDCDCED$
    local doctype, version, did = split_uri:match(hsr:read_message("Fields[uri]"))
    if not doctype then
        inject_error(hsr, "uri", "invalid URI")
        return
    end

    local timestamp = hsr:read_message("Timestamp")
    local msg = {
        Type        = "pioneer",
        Timestamp   = timestamp,
        Hostname    = hsr:read_message("Hostname"),
        -- Note: 'Hostname' is the host name of the server that received the
        -- message,
        Fields      = {
            docType         = doctype,
            sourceVersion   = version,
            documentId      = did
            }
        }

    local schema = schemas[doctype]
    if schema then schema = schema[version] end

    if not schema then
        inject_error(hsr, "schema", string.format("no schema: %s ver: %d", doctype, version), msg.Fields)
        return
    end

    if city_db then
        local xff = hsr:read_message("Fields[X-Forwarded-For]")
        local remote_addr = hsr:read_message("Fields[remote_addr]")
        msg.Fields.geoCountry = get_geo_country(xff, remote_addr)
        msg.Fields.geoCity = get_geo_city(xff, remote_addr)
    end

    if dedupe then
        local added, delta = dedupe:add(did, msg.Timestamp)
        if not added then
            msg.Type = "pioneer.duplicate"
            duplicateDelta.value = delta
            msg.Fields.duplicateDelta = duplicateDelta
            pcall(inject_message, msg)
            return
        end
    end

    if process_json(hsr, msg, schema) then
        local ok, err = pcall(inject_message, msg)
        if not ok then
            -- Note: we do NOT pass the extra message fields here,
            -- since it's likely that would simply hit the same
            -- error when injecting.
            inject_error(hsr, "inject_message", err)
            return
        end
    end
end


function transform_message(hsr)
    if geoip then
        -- reopen city_db once an hour
        local current_hour = floor(os.time() / 3600)
        if current_hour > hour then
            city_db:close()
            city_db = assert(geoip.open(cfg.city_db_file))
            hour = current_hour
        end
    end
    process_message(hsr)
end


local hsr = create_stream_reader("decoders.moz_pioneer.jose")
function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
