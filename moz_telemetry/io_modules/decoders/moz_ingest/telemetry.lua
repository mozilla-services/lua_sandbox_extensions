-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_ingest_telemetry = {
    -- String used to specify the schema location on disk. The path should
    -- contain one directory for each docType and the files in the directory
    -- must be named <docType>.<version>.schema.json. If the schema file is not
    -- found for a docType/version combination, the default schema is used to
    -- verify the document is a valid json object.
    -- e.g., main/main.4.schema.json
    schema_path = "/mnt/work/mozilla-pipeline-schemas/schemas/telemetry",

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
- throws on error

### decode

Decode and inject the message given as argument, using a module-internal stream reader.

*Arguments*
- msg (string) - Heka protobuf string to decode

*Return*
- throws on error
--]]


-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")

local rjson  = require "rjson"
local lpeg   = require "lpeg"
local crc32  = require "zlib".crc32
local miu    = require "moz_ingest.util"
local mtn    = require "moz_telemetry.normalize"
local dt     = require "lpeg.date_time"
local os     = require "os"
local table  = require "table"

local read_config          = read_config
local assert               = assert
local error                = error
local ipairs               = ipairs
local create_stream_reader = create_stream_reader
local inject_message       = inject_message
local type                 = type
local tonumber             = tonumber
local tostring             = tostring
local pcall                = pcall

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local cfg = read_config(module_cfg)
assert(type(cfg) == "table", module_cfg .. " must be a table")
assert(type(cfg.schema_path) == "string", "schema_path must be set")
if not cfg.inject_raw then cfg.inject_raw = false end
assert(type(cfg.inject_raw) == "boolean", "inject_raw must be a boolean")
local schemas = miu.load_json_schemas(cfg.schema_path)
local default_schema = rjson.parse_schema([[
{
  "$schema" : "http://json-schema.org/draft-04/schema#",
  "type" : "object",
  "title" : "default_schema",
  "properties" : {
  },
  "required" : []
}
]])

local uri_dimensions        = {"documentId", "docType","appName","appVersion","appUpdateChannel","appBuildId"}
local uri_dimensions_size   = #uri_dimensions
local uri_max_length        = 10240

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
        "gc",
        },
    }
extract_payload_objects["saved-session"] = extract_payload_objects["main"]

local environment_objects = {
    "addons",
    "build",
    "experiments",
    "partner",
    "profile",
    "settings",
    "system",
    }

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

local function split_path(s)
    if type(s) ~= "string" then return {} end
    return lpeg.match(path_grammar, s)
end

local function process_uri(hsr, msg)
    -- Path should be of the form: ^/submit/telemetry/id[/extra/path/components]$
    local path = hsr:read_message("Fields[uri]")

    local pathLength = string.len(path)
    if pathLength > uri_max_length then
        error(string.format("uri\tPath too long: %d > %d", pathLength, uri_max_length), 0)
    end

    local components = split_path(path)
    if not components or #components < 3 then
        error("uri\tNot enough path components", 0)
    end

    local submit = table.remove(components, 1)
    if submit ~= "submit" then
        error(string.format("uri\tInvalid path prefix: '%s' in %s", submit, path), 0)
    end

    local namespace = table.remove(components, 1)
    if namespace ~= "telemetry" then
        error(string.format("uri\tInvalid namespace prefix: '%s' in %s", namespace, path), 0)
    end
    msg.Logger = namespace

    local num_components = #components
    if num_components > 0 then
        if uri_dimensions_size >= num_components then
            for i=1,num_components do
                msg.Fields[uri_dimensions[i]] = components[i]
            end
        else
            error("uri\tdimension spec/path component mismatch", 0)
        end
    end
    msg.Fields.normalizedChannel = mtn.channel(msg.Fields.appUpdateChannel)
end


local function remove_objects(msg, doc, section, objects)
    if type(objects) ~= "table" then return end

    local v = doc:find(section)
    if not v then return end

    for i, name in ipairs(objects) do
        local fieldname = string.format("%s.%s", section, name)
        msg.Fields[fieldname] = doc:make_field(doc:remove_shallow(v, name))
    end
end


local function validate_schema(hsr, msg, doc, version)
    local schema = default_schema
    local dt = schemas[msg.Fields.docType or ""]
    if dt then
        version = tonumber(version)
        if not version then version = 1 end
        schema = dt[version] or default_schema
    end

    ok, err = doc:validate(schema)
    if not ok then
        error(string.format("json\t%s schema version %s validation error: %s",
                            msg.Fields.docType, tostring(version), err), 0)
    end
end


local submissionField = {value = nil, representation = "json"}
local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local function process_json(hsr, msg)
    local ok, err = pcall(doc.parse_message, doc, hsr, "Fields[content]", nil, nil, true)
    if not ok then
        -- TODO: check for gzip errors and classify them properly
        error(string.format("json\tinvalid submission: %s", err), 0)
    end

    local clientId
    local ver = doc:value(doc:find("ver"))

    if ver then
        validate_schema(hsr, msg, doc, ver)
        if ver == 3 then
            -- Special case for FxOS FTU pings
            submissionField.value = doc
            msg.Fields.submission = submissionField
            msg.Fields.sourceVersion = tostring(ver)
        else
            -- Old-style telemetry.
            local info = doc:find(info)
            -- the info object should exist because we passed schema validation (maybe)
            -- if type(info) == nil then
            --     error(string.format("schema\tmissing info object"), 0)
            -- end
            submissionField.value = doc
            msg.Fields.submission = submissionField
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
        local sourceVersion = doc:value(doc:find("version"))
        validate_schema(hsr, msg, doc, sourceVersion)
        submissionField.value = doc
        msg.Fields.submission = submissionField
        local cts = doc:value(doc:find("creationDate"))
        if cts then
            msg.Fields.creationTimestamp = dt.time_to_ns(dt.rfc3339:match(cts))
        end
        msg.Fields.reason               = doc:value(doc:find("payload", "info", "reason"))
        msg.Fields.os                   = doc:value(doc:find("environment", "system", "os", "name"))
        msg.Fields.telemetryEnabled     = doc:value(doc:find("environment", "settings", "telemetryEnabled"))
        msg.Fields.activeExperimentId   = doc:value(doc:find("environment", "addons", "activeExperiment", "id"))
        msg.Fields.clientId             = doc:value(doc:find("clientId"))
        msg.Fields.sourceVersion        = sourceVersion
        msg.Fields.docType              = doc:value(doc:find("type"))

        local app = doc:find("application")
        msg.Fields.appName              = doc:value(doc:find(app, "name"))
        msg.Fields.appVersion           = doc:value(doc:find(app, "version"))
        msg.Fields.appBuildId           = doc:value(doc:find(app, "buildId"))
        msg.Fields.appUpdateChannel     = doc:value(doc:find(app, "channel"))
        msg.Fields.appVendor            = doc:value(doc:find(app, "vendor"))

        remove_objects(msg, doc, "environment", environment_objects)
        remove_objects(msg, doc, "payload", extract_payload_objects[msg.Fields.docType])
        -- /new code
    elseif doc:value(doc:find("deviceinfo")) ~= nil then
        -- Old 'appusage' ping, see Bug 982663
        msg.Fields.docType = "appusage"
        validate_schema(hsr, msg, doc, 3)
        submissionField.value = doc
        msg.Fields.submission = submissionField

        -- Special version for this old format
        msg.Fields.sourceVersion = "3"

        local av = doc:value(doc:find("deviceinfo", "platform_version"))
        local auc = doc:value(doc:find("deviceinfo", "update_channel"))
        local abi = doc:value(doc:find("deviceinfo", "platform_build_id"))

        -- Get some more dimensions.
        msg.Fields.appName = "FirefoxOS"
        msg.Fields.appVersion = av or UNK_DIM
        msg.Fields.appUpdateChannel = auc or UNK_DIM
        msg.Fields.appBuildId = abi or UNK_DIM
        msg.Fields.normalizedChannel = mtn.channel(auc)

        -- The "telemetryEnabled" flag does not apply to this type of ping.
    elseif doc:value(doc:find("v")) then
        -- This is a Fennec "core" ping
        local sourceVersion = doc:value(doc:find("v"))
        validate_schema(hsr, msg, doc, sourceVersion)
        msg.Fields.sourceVersion = tostring(sourceVersion)
        clientId = doc:value(doc:find("clientId"))
        msg.Fields.clientId = clientId
        submissionField.value = doc
        msg.Fields.submission = submissionField
    else
        -- Everything else. Just store the submission in the submission field by default.
        validate_schema(hsr, msg, doc, 1)
        submissionField.value = doc
        msg.Fields.submission = submissionField
    end

    if type(msg.Fields.clientId) == "string" then
        msg.Fields.sampleId = crc32()(msg.Fields.clientId) % 100
    end
end


function transform_message(hsr, msg)
    if cfg.inject_raw then
        pcall(inject_message, hsr) -- duplicate the raw message
    end

    if not msg then
        msg = miu.new_message(hsr)
    end

    -- preserve the legacy telemetry behavior, todo these should eventually be deprecated
    msg.Type                    = "telemetry"
    msg.Fields.submissionDate   = os.date("%Y%m%d", msg.Timestamp / 1e9)
    msg.Fields.sourceName       = "telemetry"
    --

    process_uri(hsr, msg)
    process_json(hsr, msg)

    -- Migrate the original message data after the validation (avoids Field duplication in the error message)
    msg.EnvVersion = hsr:read_message("EnvVersion")
    msg.Hostname   = hsr:read_message("Hostname")
    -- Note: 'Hostname' is the host name of the server that received the
    -- message, while 'Host' is the name of the HTTP endpoint the client
    -- used (such as "incoming.telemetry.mozilla.org").
    msg.Fields.Host                     = hsr:read_message("Fields[Host]")
    msg.Fields.DNT                      = hsr:read_message("Fields[DNT]")
    msg.Fields.Date                     = hsr:read_message("Fields[Date]")
    msg.Fields["X-PingSender-Version"]  = hsr:read_message("Fields[X-PingSender-Version]")

    local ok, err = pcall(inject_message, msg)
    if not ok then
        error("inject_message\t" .. err, 0)
    end
end


local hsr = create_stream_reader("decoders.moz_ingest.telemetry")
function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
