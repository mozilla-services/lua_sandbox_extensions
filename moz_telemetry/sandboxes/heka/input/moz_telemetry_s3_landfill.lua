-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Landfill Data S3 Input

Retrieves/reads each file from the `s3_file_list`. The primary use of this
sandbox is to backfill the telemetry folder or to test new data
transformation/validation sandboxes.

## Sample Configuration
```lua
filename        = "moz_telemetry_s3_landfill.lua"
s3_bucket       = "net-mozaws-prod-us-west-2-pipeline-data"
s3_file_list    = "landfill_dims.ls.1"
tmp_dir         = "/mnt/work/tmp"
schema_path     = "./mozilla-pipeline-schemas"
```
--]]

require "rjson"
require "io"
require "lpeg"
require "string"
require "table"
local crc32 = require "zlib".crc32()
local mtn   = require "moz_telemetry.normalize"
local dt    = require "lpeg.date_time"

local tmp_dir       = read_config("tmp_dir")
local s3_bucket     = read_config("s3_bucket") or error("s3_bucket must be set")
local schema_path   = read_config("schema_path") or error("schema_path must be set")
local logger        = read_config("Logger")
local s3_file_list  = assert(io.open(read_config("s3_file_list")))

local schemas = {}
local function load_schemas()
    local schema_files = {
        main    = string.format("%s/telemetry/main.schema.json", schema_path),
        crash   = string.format("%s/telemetry/crash.schema.json", schema_path),
        }
    for k,v in pairs(schema_files) do
        local fh = assert(io.input(v))
        local schema = fh:read("*a")
        schemas[k] = rjson.parse_schema(schema)
    end
end
load_schemas()
schemas["saved-session"] = schemas.main

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

local emsg = {
    Logger = read_config("Logger"),
    Hostname = read_config("Hostname"),
    Type = "telemetry.error",
    Fields = {
        DecodeErrorType = "",
        DecodeError     = "",
    }
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


local function process_uri(hsr)
    -- Path should be of the form: ^/submit/namespace/id[/extra/path/components]$
    local path = hsr:read_message("Fields[Path]")

    local components = split_path(path)
    if not components or #components < 3 then
        emsg.Fields.DecodeErrorType = "uri"
        emsg.Fields.DecodeError = "Not enough path components"
        pcall(inject_message, emsg)
        return
    end

    local submit = table.remove(components, 1)
    if submit ~= "submit" then
        emsg.Fields.DecodeErrorType = "uri"
        emsg.Fields.DecodeError = string.format("Invalid path prefix: '%s' in %s", submit, path)
        pcall(inject_message, emsg)
        return
    end

    local namespace = table.remove(components, 1)
    local cfg = uri_config[namespace]
    if not cfg then
        emsg.Fields.DecodeErrorType = "uri"
        emsg.Fields.DecodeError = string.format("Invalid namespace: '%s' in %s", namespace, path)
        pcall(inject_message, emsg)
        return
    end

    local pathLength = string.len(path)
    if pathLength > cfg.max_path_length then
        emsg.Fields.DecodeErrorType = "uri"
        emsg.Fields.DecodeError = string.format("Path too long: %d > %d", pathLength, cfg.max_path_length)
        pcall(inject_message, emsg)
        return
    end

    local msg = {
        Logger = cfg.logger or namespace,
        Fields = {documentId = table.remove(components, 1)},
        }

    local num_components = #components
    if num_components > 0 then
        local dims = cfg.dimensions
        if dims and #dims >= num_components then
            for i=1,num_components do
                msg.Fields[dims[i]] = components[i]
            end
        else
            emsg.Fields.DecodeErrorType = "uri"
            emsg.Fields.DecodeError = string.format("dimension spec/path component mismatch")
            pcall(inject_message, emsg)
            return
        end
    end

    local schema
    if msg.Fields.docType then
        schema = schemas[msg.Fields.docType]
    end

    if not schema then
        emsg.Fields.DecodeErrorType = "uri"
        emsg.Fields.DecodeError = string.format("docType: %s does not have a validation schema", tostring(msg.Fields.docType))
        pcall(inject_message, emsg)
        return
    end

    return msg, schema
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
    local ok, doc = pcall(rjson.parse_message, hsr, "Fields[submission]")
    if not ok then
        emsg.Fields.DecodeErrorType = "json"
        emsg.Fields.DecodeError = string.format("invalid submission: %s", doc)
        pcall(inject_message, emsg)
        return false
    end

    local ok, err = doc:validate(schema)
    if not ok then
        emsg.Fields.DecodeErrorType = "json"
        emsg.Fields.DecodeError = string.format("%s schema validation error: %s", msg.Fields.docType, err)
        pcall(inject_message, emsg)
        return false
    end

    msg.Fields.creationTimestamp    = dt.time_to_ns(dt.rfc3339:match(doc:value(doc:find("creationDate"))))
    msg.Fields.reason               = doc:value(doc:find("payload", "info", "reason"))
    msg.Fields.os                   = doc:value(doc:find("environment", "system", "os", "name"))
    msg.Fields.telemetryEnabled     = doc:value(doc:find("environment", "settings", "telemetryEnabled"))
    msg.Fields.activeExperimentId   = doc:value(doc:find("environment", "addons", "activeExperiment", "id"))
    msg.Fields.clientId             = doc:value(doc:find("clientId"))
    msg.Fields.sourceVersion        = doc:value(doc:find("version"))
    msg.Fields.docType              = doc:value(doc:find("type"))
    msg.Fields.sampleId             = crc32(msg.Fields.clientId) % 100

    local app = doc:find("application")
    msg.Fields.appName              = doc:value(doc:find(app, "name"))
    msg.Fields.appVersion           = doc:value(doc:find(app, "version"))
    msg.Fields.appBuildId           = doc:value(doc:find(app, "buildId"))
    msg.Fields.appUpdateChannel     = doc:value(doc:find(app, "channel"))
    msg.Fields.normalizedChannel    = mtn.channel(msg.Fields.appUpdateChannel)
    msg.Fields.appVendor            = doc:value(doc:find(app, "vendor"))

    remove_objects(msg, doc, "environment", environment_objects)
    remove_objects(msg, doc, "payload", extract_payload_objects[msg.Fields.docType])
    return true
end


local function process_file(hsr, fn)
    local fh, err =  io.open(fn)
    if not fh then
        print("failed to open", fn)
        return
    end

    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh)
            if found then
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
                    msg.Fields.submissionDate  = hsr:read_message("Fields[submissionDate]")
                    msg.Fields.sourceName      = "telemetry"

                    if process_json(hsr, msg, schema) then
                        local ok, err = pcall(inject_message, msg)
                        if not ok then
                            emsg.Fields.DecodeErrorType = "inject_message"
                            emsg.Fields.DecodeError = err
                            pcall(inject_message, emsg)
                        end
                    end
                end
            end
        until not found
    until read == 0
    fh:close()
end


local function execute_cmd(cmd, retries)
    local rv = 1
    for i=1, retries do
        rv = os.execute(cmd)
        if rv == 0 then
            break
        end
    end
    return rv
end


function process_message()
    local hsr = create_stream_reader("s3")

    for fn in s3_file_list:lines() do
        local tfn = string.format("%s/%s", tmp_dir, logger)
        local cmd = string.format("aws s3 cp s3://%s/%s %s", s3_bucket, fn, tfn)
        print("processing", cmd)
        local rv = execute_cmd(cmd, 3)
        if rv == 0 then
            process_file(hsr, tfn)
        else
            print("failed to execute rv:", rv, " cmd:", cmd)
        end
    end
    return 0
end
