-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Ingestion Utility Module

## Functions

### new_message

Returns a new message table based on a moz_ingest uri/message.

*Arguments*
- hsr (userdata) - Heka stream reader

*Return*
- msg (table/error) - base message table before the namespace specific
transformation

### load_json_schemas

Returns a table of rjson schemas key by namespace and version.

*Arguments*
- schema_path (string) - Directory containing the JSON schemas

*Return*
- schemas (table)

--]]

-- Imports
local io        = require "io"
local lfs       = require "lfs"
local l         = require "lpeg"
l.locale(l)
local rjson     = require "rjson"
local string    = require "string"

local assert    = assert
local error     = error
local pcall     = pcall
local tonumber  = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

-- ^/submit/telemetry/docid[/doctype]
local element = l.P"/" * l.C((1 - l.P"/")^1)
local telemetry_uri = l.P"/submit/" * l.C"telemetry" * element * element^-1
-- ^/submit/<namespace>/<doctype>/<docversion>[/<docid>]
local generic_uri = l.P"/submit" * element * element * l.P"/" * (l.digit^1/tonumber) * element^-1

function new_message(hsr)
    local namespace, doctype, version, did
    local uri = hsr:read_message("Fields[uri]") or error("missing uri", 0)
    namespace, did, doctype = telemetry_uri:match(uri)
    if not namespace then
        namespace, doctype, version, did = generic_uri:match(uri)
    end

    if not namespace then
        error("invalid uri", 0)
    end

    return {
        Timestamp = hsr:read_message("Timestamp"),
        Logger    = namespace,
        Type      = "validated",
        Fields    = {
            documentId    = did,
            docType       = doctype,
            sourceVersion = version,
            -- migrate geo if it is already available (i.e., backfill)
            geoCountry    = hsr:read_message("Fields[geoCountry]"),
            geoCity       = hsr:read_message("Fields[geoCity]")
        }
    }
end


function load_json_schemas(schema_path)
    local schemas = {}
    for dn in lfs.dir(schema_path) do
        local fqdn = string.format("%s/%s", schema_path, dn)
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
    return schemas
end

return M
