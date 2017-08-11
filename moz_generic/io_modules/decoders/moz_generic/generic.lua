-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Generic Ingestion Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_generic = {
    -- String used to specify the schema location on disk. The path should
    -- contain directories for each namespace and docType and the files in
    -- the namespace directories must be named <docType>.<version>.schema.json.
    -- e.g., generic/testping/testping.4.schema.json
    schema_path = "/mnt/work/mozilla-pipeline-schemas/schemas",

    -- String used to specify the message field containing the user submitted payload.
    content_field = "Fields[content]", -- optional, default shown

    -- String used to specify the message field containing the URI of the submission.
    uri_field = "Fields[uri]", -- optional, default shown

    -- String used to specify GeoIP city database location on disk.
    city_db_file = "/mnt/work/geoip/city.db", -- optional, if not specified no geoip lookup is performed

    -- Boolean used to determine whether to inject the raw message in addition to the decoded one.
    inject_raw = false, -- optional, if not specified the raw message is not injected

    -- WARNING if the cuckoo filter settings are altered the plugin's
    -- `preservation_version` should be incremented
    -- number of items in each de-duping cuckoo filter partition
    cf_items = 32e6, -- optional, if not provided de-duping is disabled

    -- number of partitions, each containing `cf_items`
    -- cf_partitions = 4 -- optional default 4 (1, 2, 4, 8, 16)

    -- interval size in minutes for cuckoo filter pruning
    -- cf_interval_size = 6, -- optional, default 6 (25.6 hours)
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

_PRESERVATION_VERSION = read_config("preservation_version") or _PRESERVATION_VERSION or 0

-- Imports
local module_name   = ...
local string        = require "string"
local table         = require "table"
local module_cfg    = string.gsub(module_name, "%.", "_")

local rjson  = require "rjson"
local io     = require "io"
local lfs    = require "lfs"
local lpeg   = require "lpeg"
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
local type                 = type
local tonumber             = tonumber
local tostring             = tostring
local pcall                = pcall
local geoip
local city_db
local dedupe
local duplicateDelta

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

    if cfg.cf_items then
        if not cfg.cf_interval_size then cfg.cf_interval_size = 6 end
        if cfg.cf_partitions then
            local x = cfg.cf_partitions
            assert(type(cfg.cf_partitions) == "number" and x == 1 or x == 2 or x == 4 or x == 8 or x == 16,
                    "cf_partitions [1,2,4,8,16]")
        else
            cfg.cf_partitions = 4
        end
        local cfe = require "cuckoo_filter_expire"
        dedupe = {}
        for i=1, cfg.cf_partitions do
            local name = "g_mtp_dedupe" .. tostring(i)
            _G[name] = cfe.new(cfg.cf_items, cfg.cf_interval_size) -- global scope so they can be preserved
            dedupe[i] = _G[name] -- use a local array for access
                                 -- optimization to reduce the restoration memory allocation and time
        end
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
    for namespace in lfs.dir(cfg.schema_path) do
        for dn in lfs.dir(string.format("%s/%s", cfg.schema_path, namespace)) do
            local fqdn = string.format("%s/%s/%s", cfg.schema_path, namespace, dn)
            local mode = lfs.attributes(fqdn, "mode")
            if mode == "directory" and not dn:match("^%.") then
                for fn in lfs.dir(fqdn) do
                    local name, version = fn:match("(.+)%.(%d+).schema%.json$")
                    if name then
                        local fh = assert(io.input(string.format("%s/%s", fqdn, fn)))
                        local schema = fh:read("*a")
                        local n = schemas[namespace]
                        if not n then
                            n = {}
                            schemas[namespace] = n
                        end
                        local s = schemas[namespace][name]
                        if not s then
                            s = {}
                            schemas[namespace][name] = s
                        end
                        local ok, rjs = pcall(rjson.parse_schema, schema)
                        if not ok then error(string.format("%s: %s", fn, rjs)) end
                        s[tonumber(version)] = rjs
                    end
                end
            end
        end
    end
end
load_schemas()

local uri_config = {
    moz_generic = {
        dimensions      = {"docType","docVersion","documentId"},
        max_path_length = 1024,
        logger          = "moz_generic"
    },
}

--[[
Read the raw message, annotate it with our error information, and attempt to inject it.
--]]
local function inject_error(hsr, err_type, err_msg, extra_fields)
    local len
    local raw = hsr:read_message("raw")
    local err = decode_message(raw)
    err.Logger = "moz_generic"
    err.Type = "moz_generic.error"
    if not err.Fields then
        err.Fields = {}
    else
        len = #err.Fields
        for i = len, 1, -1  do
            local name = err.Fields[i].name
            if name == "X-Forwarded-For" or name == "RemoteAddr" then
                table.remove(err.Fields, i)
            end
        end
    end
    len = #err.Fields
    if not extra_fields or not extra_fields.submissionDate then
        len = len + 1
        err.Fields[len] = { name="submissionDate", value=os.date("%Y%m%d", err.Timestamp / 1e9) }
    end
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
local hsr           = create_stream_reader("decoders.moz_generic.generic")

local function split_path(s)
    if type(s) ~= "string" then return {} end
    return lpeg.match(path_grammar, s)
end


local function process_uri(hsr)
    -- Path should be of the form: ^/submit/namespace/doctype/docversion[/docid]$
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

    local ucfg = uri_config['moz_generic']

    local pathLength = string.len(path)
    if pathLength > ucfg.max_path_length then
        inject_error(hsr, "uri", string.format("Path too long: %d > %d", pathLength, ucfg.max_path_length))
        return
    end

    local msg = {
        Timestamp = hsr:read_message("Timestamp"),
        Logger    = ucfg.logger or namespace,
        Fields    = {
            namespace   = namespace,
            args        = hsr:read_message("Fields[args]"),
            geoCountry  = hsr:read_message("Fields[geoCountry]"),
            geoCity     = hsr:read_message("Fields[geoCity]")
            }
        }

    -- insert geo info if necessary
    if city_db and not msg.Fields.geoCountry then
        local xff = hsr:read_message("Fields[X-Forwarded-For]")
        local remote_addr = hsr:read_message("Fields[RemoteAddr]")
        msg.Fields.geoCountry = get_geo_country(xff, remote_addr)
        msg.Fields.geoCity = get_geo_city(xff, remote_addr)
    end

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

    if dedupe then
        local int = string.byte(msg.Fields.documentId)
        if int > 96 then
            int = int - 39
        elseif int > 64 then
            int = int - 7
        end
        local idx = int % cfg.cf_partitions + 1
        local cf = dedupe[idx]
        local added, delta = cf:add(msg.Fields.documentId, msg.Timestamp)
        if not added then
            msg.Type = "moz_generic.duplicate"
            duplicateDelta.value = delta
            msg.Fields.duplicateDelta = duplicateDelta
            pcall(inject_message, msg)
            return
        end
    end

    return msg
end

local function validate_schema(hsr, msg, doc, version)
    local schema
    local namespace = msg.Fields.namespace or ""
    local dt = (schemas[namespace] or {})[msg.Fields.docType or ""]
    local version = tonumber(msg.Fields.docVersion or "0")
    if dt then
        if not version then version = 1 end
        schema = dt[version]
    end

    if not schema then
        inject_error(hsr, "schema", string.format("missing schema for %s version %s", msg.Fields.docType, tostring(version)), msg.Fields)
        return false
    end

    ok, err = doc:validate(schema)
    if not ok then
        inject_error(hsr, "schema", string.format("%s schema version %s validation error: %s", msg.Fields.docType, tostring(version), err), msg.Fields)
        return false
    end
    return true
end


local submissionField = {value = nil, representation = "json"}
local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local function process_json(hsr, msg)
    local ok, err = pcall(doc.parse_message, doc, hsr, cfg.content_field, nil, nil, true)
    if not ok then
        -- TODO: check for gzip errors and classify them properly
        inject_error(hsr, "json", string.format("invalid submission: %s", err), msg.Fields)
        return false
    end

    if not validate_schema(hsr, msg, doc, ver) then return false end
    submissionField.value = doc
    msg.Fields.submission = submissionField

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
    local msg = process_uri(hsr)
    if msg then
        msg.Type        = "moz_generic"
        msg.EnvVersion  = hsr:read_message("EnvVersion")
        msg.Hostname    = hsr:read_message("Hostname")
        -- Note: 'Hostname' is the host name of the server that received the
        -- message, while 'Host' is the name of the HTTP endpoint the client
        -- used (such as "incoming.telemetry.mozilla.org").
        msg.Fields.Host            = hsr:read_message("Fields[Host]")
        msg.Fields.DNT             = hsr:read_message("Fields[DNT]")
        msg.Fields.Date            = hsr:read_message("Fields[Date]")
        msg.Fields.submissionDate  = os.date("%Y%m%d", msg.Timestamp / 1e9)

        if process_json(hsr, msg) then
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
