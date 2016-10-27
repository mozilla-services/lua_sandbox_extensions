-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Ping Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_telemetry_ping = {
    -- String used to specify the schema location on disk.
    schema_path = "/mnt/work/schemas",

    -- String used to specify the message field containing the user submitted telemetry ping.
    content_field = "Fields[content]", -- optional, default shown

    -- String used to specify the message field containing the URI of the submitted telemetry ping.
    uri_field = "Fields[uri]", -- optional, default shown

    -- String used to specify GeoIP city database location on disk.
    city_db_file = "/mnt/work/geoip/city.db", -- optional, if not specified no geoip lookup is performed

    -- Boolean used to determine whether to inject the raw message in addition to the decoded one.
    inject_raw = false, -- optional, if not specified the raw message is not injected
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
local module_cfg    = string.gsub(module_name, "%.", "_")

local rjson  = require "rjson"
local io     = require "io"
local lpeg   = require "lpeg"
local table  = require "table"
local os     = require "os"
local floor  = require "math".floor
local crc32  = require "zlib".crc32
local mtn    = require "moz_telemetry.normalize"
local dt     = require "lpeg.date_time"

local read_config          = read_config
local assert               = assert
local pairs                = pairs
local ipairs               = ipairs
local create_stream_reader = create_stream_reader
local decode_message       = decode_message
local inject_message       = inject_message
local type                 = type
local tostring             = tostring
local pcall                = pcall
local geoip
local city_db

-- create before the environment is locked down since it conditionally includes a module
local function load_decoder_cfg()
    local cfg = read_config(module_cfg)
    assert(type(cfg) == "table", module_cfg .. " must be a table")
    assert(type(cfg.schema_path) == "string", "schema_path must be set")

    -- the old values for these were Fields[submission] and Fields[Path]
    if not cfg.content_field then cfg.content_field = "Fields[content]" end
    if not cfg.uri_field then cfg.uri_field = "Fields[uri]" end
    if not cfg.inject_raw then cfg.inject_raw = false end
    assert(type(cfg.inject_raw) == "boolean", "inject_raw must be a boolean")

    if cfg.city_db_file then
        geoip = require "geoip.city"
        city_db = assert(geoip.open(cfg.city_db_file))
    end

    return cfg
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local cfg = load_decoder_cfg()
local UNK_DIM = "UNKNOWN"
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
    local schema_files = {
        ["main"]    = string.format("%s/telemetry/main.schema.json", cfg.schema_path),
        ["crash"]   = string.format("%s/telemetry/crash.schema.json", cfg.schema_path),
        ["core"]    = string.format("%s/telemetry/core.schema.json", cfg.schema_path),
        ["vacuous"] = string.format("%s/telemetry/vacuous.schema.json", cfg.schema_path),
    }
    for k,v in pairs(schema_files) do
        local fh = assert(io.input(v))
        local schema = fh:read("*a")
        schemas[k] = rjson.parse_schema(schema)
    end
end
load_schemas()
schemas["saved-session"]                        = schemas.main

local uri_config = {
    telemetry = {
        dimensions      = {"docType","appName","appVersion","appUpdateChannel","appBuildId"},
        max_path_length = 10240,
        },
    }

local extract_payload_objects = {
    main = {
        "addonDetails",
        "addonHistograms",
        "childPayloads", -- only present with e10s
        "chromeHangs",
        "fileIOReports",
        "histograms",
        "info",
        "keyedHistograms",
        "lateWrites",
        "log",
        "simpleMeasurements",
        "slowSQL",
        "slowSQLstartup",
        "threadHangStats",
        "UIMeasurements",
        },
    }

local environment_objects = {
    "addons",
    "build",
    "partner",
    "profile",
    "settings",
    "system",
    }

--[[
Read the raw message, annotate it with our error information,
and attempt to inject it.
TODO: Remove Fields[X-Forwarded-For] and Fields[RemoteAddr]
      before injecting.
--]]
local function inject_error(hsr, err_type, err_msg, extra_fields)
    local raw = hsr:read_message("raw")
    local err = decode_message(raw)
    err.Logger = "telemetry"
    err.Type = "telemetry.error"
    if type(err.Fields) ~= "table" then
        err.Fields = {}
    end
    err.Fields[#err.Fields + 1] = { name="DecodeErrorType", value=err_type }
    err.Fields[#err.Fields + 1] = { name="DecodeError",     value=err_msg }

    if type(extra_fields) == "table" then
        -- Add these optional fields to the raw message.
        for k,v in pairs(extra_fields) do
            err.Fields[#err.Fields + 1] = { name=k, value=v }
        end
    end
    pcall(inject_message, err)
end

--[[
Split a path into components. Multiple consecutive separators do not
result in empty path components.
Examples:
  /foo/bar      ->   {"foo", "bar"}
  ///foo//bar/  ->   {"foo", "bar"}
  foo/bar/      ->   {"foo", "bar"}
  /             ->   {}
--]]
local sep           = lpeg.P("/")
local elem          = lpeg.C((1 - sep)^1)
local path_grammar  = lpeg.Ct(elem^0 * (sep^0 * elem)^0)
local hsr           = create_stream_reader("decoders.moz_telemetry.ping")

local function split_path(s)
    if type(s) ~= "string" then return {} end
    return lpeg.match(path_grammar, s)
end


local function process_uri(hsr)
    -- Path should be of the form: ^/submit/namespace/id[/extra/path/components]$
    local path = hsr:read_message(cfg.uri_field)

    local components = split_path(path)
    if not components or #components < 3 then
        inject_error(hsr, "uri", "Not enough path components")
        return
    end

    local submit = table.remove(components, 1)
    if submit ~= "submit" then
        inject_error(hsr, "uri", string.format("Invalid path prefix: '%s' in %s", submit, path))
        return
    end

    local namespace = table.remove(components, 1)
    local ucfg = uri_config[namespace]
    if not ucfg then
        inject_error(hsr, "uri", string.format("Invalid namespace: '%s' in %s", namespace, path))
        return
    end

    local pathLength = string.len(path)
    if pathLength > ucfg.max_path_length then
        inject_error(hsr, "uri", string.format("Path too long: %d > %d", pathLength, ucfg.max_path_length))
        return
    end

    local msg = {
        Logger = ucfg.logger or namespace,
        Fields = {documentId = table.remove(components, 1)},
        }

    local num_components = #components
    if num_components > 0 then
        local dims = ucfg.dimensions
        if dims and #dims >= num_components then
            for i=1,num_components do
                msg.Fields[dims[i]] = components[i]
            end
        else
            inject_error(hsr, "uri", "dimension spec/path component mismatch", msg.Fields)
            return
        end
    end

    return msg, schemas[msg.Fields.docType] or schemas.vacuous
end


local function remove_objects(msg, doc, section, objects)
    if type(objects) ~= "table" then return end

    local v = doc:find(section)
    if not v then return end

    for i, name in ipairs(objects) do
        local fieldname = string.format("%s.%s", section, name)
        msg.Fields[fieldname] = doc:remove(v, name)
    end
end


local function process_json(hsr, msg, schema)
    local ok, doc = pcall(rjson.parse_message, hsr, cfg.content_field)
    if not ok then
        -- TODO: check for gzip errors and classify them properly
        inject_error(hsr, "json", string.format("invalid submission: %s", doc), msg.Fields)
        return false
    end

    local ok, err = doc:validate(schema)
    if not ok then
        inject_error(hsr, "json", string.format("%s schema validation error: %s", msg.Fields.docType, err), msg.Fields)
        return false
    end

    local clientId
    local ver = doc:value(doc:find("ver"))

    if ver then
        if ver == 3 then
            -- Special case for FxOS FTU pings
            msg.Fields.submission = doc
            msg.Fields.sourceVersion = tostring(ver)

            -- Get some more dimensions.
            local channel = msg.Fields.appUpdateChannel
            if channel and type(channel) == "string" then
                msg.Fields.normalizedChannel = mtn.channel(channel)
            end
        else
            -- Old-style telemetry.
            local info = doc:find(info)
            -- the info object should exist because we passed schema validation (maybe)
            -- if type(info) == nil then
            --     inject_error(hsr, "schema", string.format("missing info object"), msg.Fields)
            -- end
            msg.Fields.submission = doc
            msg.Fields.sourceVersion = tostring(ver)

            -- Get some more dimensions.
            msg.Fields.docType           = doc:value(doc:find(info, "reason")) or UNK_DIM
            msg.Fields.appName           = doc:value(doc:find(info, "appName")) or UNK_DIM
            msg.Fields.appVersion        = doc:value(doc:find(info, "appVersion")) or UNK_DIM
            msg.Fields.appUpdateChannel  = doc:value(doc:find(info, "appUpdateChannel")) or UNK_DIM
            msg.Fields.appBuildId        = doc:value(doc:find(info, "appBuildID")) or UNK_DIM
            msg.Fields.normalizedChannel = mtn.channel(doc:value(doc:find(info, "appUpdateChannel")))

            -- Old telemetry was always "enabled"
            msg.Fields.telemetryEnabled = true

            -- Do not want default values for these.
            msg.Fields.os = doc:value(doc:find(info, "OS"))
            msg.Fields.appVendor = doc:value(doc:find(info, "vendor"))
            msg.Fields.reason = doc:value(doc:find(info, "reason"))
            clientId = doc:value(doc:find("clientID")) -- uppercase ID is correct
            msg.Fields.clientId = clientId
        end
    elseif doc:value(doc:find("version")) then
        -- new code
        msg.Fields.submission           = doc
        local cts = doc:value(doc:find("creationDate"))
        if cts then
            msg.Fields.creationTimestamp = dt.time_to_ns(dt.rfc3339:match(cts))
        end
        msg.Fields.reason               = doc:value(doc:find("payload", "info", "reason"))
        msg.Fields.os                   = doc:value(doc:find("environment", "system", "os", "name"))
        msg.Fields.telemetryEnabled     = doc:value(doc:find("environment", "settings", "telemetryEnabled"))
        msg.Fields.activeExperimentId   = doc:value(doc:find("environment", "addons", "activeExperiment", "id"))
        msg.Fields.clientId             = doc:value(doc:find("clientId"))
        msg.Fields.sourceVersion        = doc:value(doc:find("version"))
        msg.Fields.docType              = doc:value(doc:find("type"))

        local app = doc:find("application")
        msg.Fields.appName              = doc:value(doc:find(app, "name"))
        msg.Fields.appVersion           = doc:value(doc:find(app, "version"))
        msg.Fields.appBuildId           = doc:value(doc:find(app, "buildId"))
        msg.Fields.appUpdateChannel     = doc:value(doc:find(app, "channel"))
        msg.Fields.normalizedChannel    = mtn.channel(msg.Fields.appUpdateChannel)
        msg.Fields.appVendor            = doc:value(doc:find(app, "vendor"))

        remove_objects(msg, doc, "environment", environment_objects)
        remove_objects(msg, doc, "payload", extract_payload_objects[msg.Fields.docType])
        -- /new code
    elseif doc:value(doc:find("deviceinfo")) ~= nil then
        -- Old 'appusage' ping, see Bug 982663
        msg.Fields.submission           = doc

        -- Special version for this old format
        msg.Fields.sourceVersion = "3"

        local av = doc:value(doc:find("deviceinfo", "platform_version"))
        local auc = doc:value(doc:find("deviceinfo", "update_channel"))
        local abi = doc:value(doc:find("deviceinfo", "platform_build_id"))

        -- Get some more dimensions.
        msg.Fields.docType = "appusage"
        msg.Fields.appName = "FirefoxOS"
        msg.Fields.appVersion = av or UNK_DIM
        msg.Fields.appUpdateChannel = auc or UNK_DIM
        msg.Fields.appBuildId = abi or UNK_DIM
        msg.Fields.normalizedChannel = mtn.channel(auc)

        -- The "telemetryEnabled" flag does not apply to this type of ping.
    elseif doc:value(doc:find("v")) then
        -- This is a Fennec "core" ping
        msg.Fields.sourceVersion = tostring(doc:value(doc:find("v")))
        clientId = doc:value(doc:find("clientId"))
        msg.Fields.clientId = clientId
        msg.Fields.submission = doc
    else
        -- Everything else. Just store the submission in the submission field by default.
        msg.Fields.submission = doc
    end

    if type(msg.Fields.clientId) == "string" then
        msg.Fields.sampleId = crc32()(msg.Fields.clientId) % 100
    end

    return true
end

function transform_message(hsr)
    if cfg.inject_raw then
        -- duplicate the raw message
        pcall(inject_message, hsr)
    end

    if geoip then
        -- reopen city_db once an hour
        local current_hour = floor(os.time() / 3600)
        if current_hour > hour then
            city_db:close()
            city_db = assert(geoip.open(cfg.city_db_file))
            hour = current_hour
        end
    end

    local msg, schema = process_uri(hsr)
    if msg then
        msg.Type        = "telemetry"
        msg.Timestamp   = hsr:read_message("Timestamp")
        msg.EnvVersion  = hsr:read_message("EnvVersion")
        msg.Hostname    = hsr:read_message("Hostname")
        -- Note: 'Hostname' is the host name of the server that received the
        -- message, while 'Host' is the name of the HTTP endpoint the client
        -- used (such as "incoming.telemetry.mozilla.org").
        msg.Fields.Host            = hsr:read_message("Fields[Host]")
        msg.Fields.DNT             = hsr:read_message("Fields[DNT]")
        msg.Fields.Date            = hsr:read_message("Fields[Date]")
        msg.Fields.geoCountry      = hsr:read_message("Fields[geoCountry]")
        msg.Fields.geoCity         = hsr:read_message("Fields[geoCity]")
        msg.Fields.submissionDate  = os.date("%Y%m%d", hsr:read_message("Timestamp") / 1e9)
        msg.Fields.sourceName      = "telemetry"

        -- insert geo info if necessary
        if city_db and not msg.Fields.geoCountry then
            local xff = hsr:read_message("Fields[X-Forwarded-For]")
            local remote_addr = hsr:read_message("Fields[RemoteAddr]")
            msg.Fields.geoCountry = get_geo_country(xff, remote_addr)
            msg.Fields.geoCity = get_geo_city(xff, remote_addr)
        end

        if process_json(hsr, msg, schema) then
            local ok, err = pcall(inject_message, msg)
            if not ok then
                -- Note: we do NOT pass the extra message fields here,
                -- since it's likely that would simply hit the same
                -- error when injecting.
                inject_error(hsr, "inject_message", err)
            end
        end
    end
end

function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
