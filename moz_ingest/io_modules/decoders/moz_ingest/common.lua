-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla nginx_moz_ingest Common Decoder Module

Handles the common moz_ingest tasks such as de-duplication, geo lookup and error
handling before passing the data off to the correct subdecoder.

## Decoder Configuration Table
```lua
decoders_moz_ingest_common = {
    sub_decoders = { -- required
        -- _namespace_ (string) = Decoder module name
        -- a namespace of "*" can be used to specify a default decoder
        telemetry  = "decoders.moz_ingest.telemetry",
    },

    -- error_on_missing_sub_decoder = false, -- optional

    -- String used to specify GeoIP city database location on disk.
    city_db_file = "/usr/share/geoip/GeoIP2-City.mmdb", -- optional, if not specified no city/country geoip lookup is performed

    isp_db_file = "/usr/share/geoip/GeoIP2-ISP.mmdb", -- optional
    isp_docTypes = {"customStudy" = true} -- docTypes to perform ISP geoip lookups on, must be set if isp_db_file is defined

    -- WARNING if the cuckoo filter settings are altered the plugin's
    -- `preservation_version` should be incremented
    -- number of items in each de-duping cuckoo filter partition
    cf_items = 32e6, -- optional, if not provided de-duping is disabled

    -- number of partitions, each containing `cf_items`
    -- cf_partitions = 4 -- optional default 4

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
- throws on error

### decode

Decode and inject the message given as argument, using a module-internal stream reader.

*Arguments*
- msg (string) - Heka protobuf string to decode

*Return*
- throws on error
--]]

_PRESERVATION_VERSION = read_config("preservation_version") or _PRESERVATION_VERSION or 0

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")
local os            = require "os"
local crc32         = require "zlib".crc32
local floor         = require "math".floor
local miu           = require "moz_ingest.util"
local table         = require "table"

local assert        = assert
local pairs         = pairs
local pcall         = pcall
local setmetatable  = setmetatable

local create_stream_reader = create_stream_reader
local decode_message       = decode_message
local inject_message       = inject_message

local sub_decoders  = {}
local maxminddb
local city_db
local isp_db
local dedupe
local duplicateDelta

-- create before the environment is locked down since it conditionally includes modules
local function load_decoder_cfg()
    local cfg = read_config(module_cfg)
    assert(type(cfg) == "table", module_cfg .. " must be a table")
    if error_on_missing_sub_decoder then
        assert(type(error_on_missing_sub_decoder) == "boolean", "error_on_missing_sub_decoder must be a boolean")
    end

    if cfg.cf_items then
        if not cfg.cf_interval_size then cfg.cf_interval_size = 6 end
        if cfg.cf_partitions then
            local x = cfg.cf_partitions
            assert(type(cfg.cf_partitions) == "number")
        else
            cfg.cf_partitions = 4
        end
        local cfe = require "cuckoo_filter_expire"
        dedupe = {}
        for i=1, cfg.cf_partitions do
            local name = "g_mi_dedupe" .. tostring(i)
            _G[name] = cfe.new(cfg.cf_items, cfg.cf_interval_size) -- global scope so they can be preserved
            dedupe[i] = _G[name] -- use a local array for access
                                 -- optimization to reduce the restoration memory allocation and time
        end
        duplicateDelta = {value_type = 2, value = 0, representation = tostring(cfg.cf_interval_size) .. "m"}
    end

    if cfg.city_db_file then
        maxminddb = require "maxminddb"
        city_db = assert(maxminddb.open(cfg.city_db_file))
    end

    if cfg.isp_db_file then
        maxminddb = require "maxminddb"
        isp_db = assert(maxminddb.open(cfg.isp_db_file))
        assert(type(cfg.isp_docTypes) == "table", "isp_docTypes table must be set")
    else
        assert(cfg.isp_docTypes == nil, "isp_docTypes cannot be defined without isp_db_file")
    end

    local sd_cnt = 0
    assert(type(cfg.sub_decoders) == "table", "sub_decoders must be a table")
    for k,v in pairs(cfg.sub_decoders) do
        local t = type(v)
        if t == "string" then
            local tm = require(v).transform_message
            assert(type(tm) == "function", "sub_decoders, no transform_message function defined: " .. k)
            sub_decoders[k] = tm
            if k == "*" then
                local mt = {__index = function(t, k) return tm end }
                setmetatable(sub_decoders, mt);
            end
            sd_cnt = sd_cnt + 1
        elseif t == "boolean" and t and k == "test" then
            sd_cnt = 1
        else
            error("sub_decoder, invalid type: " .. k)
        end
    end
    assert(sd_cnt > 0, "no sub_decoders configured")

    return cfg
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local cfg = load_decoder_cfg()

local UNK_GEO = "??"
-- Track the hour to facilitate reopening city_db hourly.
local hour = floor(os.time() / 3600)

local function get_ip(db, xff, remote_addr)
    local ok, ip = pcall(db.lookup, db, xff)
    if not ok then
        ip = db:lookup(remote_addr)
    end
    return ip
end

local function get_geo_city(xff, remote_addr)
    local city = UNK_GEO
    local country = UNK_GEO

    local ok, ip = pcall(get_ip, city_db, xff, remote_addr)
    if not ok then return city, country end

    ok, city = pcall(ip.get, ip, "city", "names", "en")
    if not ok then city = UNK_GEO end

    ok, country = pcall(ip.get, ip, "country", "iso_code")
    if not ok then country = UNK_GEO end

    return city, country
end

local function get_geo_isp(xff, remote_addr)
    local isp = UNK_GEO

    local ok, ip = pcall(get_ip, isp_db, xff, remote_addr)
    if not ok then return isp end

    ok, isp = pcall(ip.get, ip, "isp")
    if not ok then isp = UNK_GEO end

    return isp
end


--[[
Read the raw message, annotate it with our error information, and attempt to inject it.
--]]
local function inject_error(hsr, namespace, err_type, err_msg, extra_fields)
    local len
    local raw  = hsr:read_message("raw")
    local err  = decode_message(raw)
    err.Logger = namespace
    if namespace == "telemetry" then
        err.Type = namespace .. ".error" -- preserve historical telemetry behavior
    else
        err.Type = "error"
    end
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
    err.Fields[len] = { name = "DecodeErrorType", value = err_type}
    len = len + 1
    err.Fields[len] = { name = "DecodeError",     value = err_msg}

    if extra_fields then
        -- Add these optional fields to the raw message.
        for k,v in pairs(extra_fields) do
            len = len + 1
            err.Fields[len] = { name = k, value = v }
        end
    end
    pcall(inject_message, err)
end


local function inject_error_helper(hsr, namespace, err, fields)
    local et, em = err:match("^(.-)\t(.+)")
    if et == "inject_message" then
        -- Note: we do NOT pass the extra message fields here,
        -- since it's likely that would simply hit the same
        -- error when injecting.
        inject_error(hsr, namespace, et, em)
    else
        if not et then
            et = "internal"
            em = err
        end
        inject_error(hsr, namespace, et, em, fields)
    end
end


function transform_message(hsr, msg)
    local uri = hsr:read_message("Fields[uri]")
    if not msg then
        local ok
        ok, msg = pcall(miu.new_message, hsr, uri)
        if not ok then
            inject_error(hsr, "moz_ingest", "uri", msg)
            return
        end
    end

    if maxminddb then
        -- reopen the geoip databases once an hour
        local current_hour = floor(os.time() / 3600)
        if current_hour > hour then
            if cfg.city_db_file then
                city_db = assert(maxminddb.open(cfg.city_db_file))
            end
            if cfg.isp_db_file then
                isp_db = assert(maxminddb.open(cfg.isp_db_file))
            end
            hour = current_hour
        end

        local xff = hsr:read_message("Fields[X-Forwarded-For]")
        local remote_addr = hsr:read_message("Fields[remote_addr]")
        msg.Fields.geoCity, msg.Fields.geoCountry = get_geo_city(xff, remote_addr)
        if cfg.isp_docTypes and cfg.isp_docTypes[msg.Fields.docType] then
            msg.Fields.geoISP = get_geo_isp(xff, remote_addr)
        end
    end

    if dedupe and msg.Fields.documentId then
        local idx = crc32()(uri) % cfg.cf_partitions + 1
        local cf = dedupe[idx]
        local added, delta = cf:add(uri, msg.Timestamp)
        if not added then
            if msg.Logger == "telemetry" then
                msg.Type = msg.Logger .. ".duplicate" -- preserve historical telemetry behavior
            else
                msg.Type = "duplicate"
            end
            duplicateDelta.value = delta
            msg.Fields.duplicateDelta = duplicateDelta
            pcall(inject_message, msg)
            return
        end
    end

    local sd = sub_decoders[msg.Logger]
    if sd then
        local ok, err = pcall(sd, hsr, msg)
        if not ok or err then
            inject_error_helper(hsr, msg.Logger, err, msg.Fields)
        end
        return
    end

    if cfg.error_on_missing_sub_decoder then
        inject_error(hsr, msg.Logger, "skipped", "no sub decoder", msg.Fields)
    end -- else drop the message
end


local hsr = create_stream_reader("decoders.moz_ingest.common")
function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
