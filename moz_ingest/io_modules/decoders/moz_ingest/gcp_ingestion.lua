-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla GCP Ingestion Decoder Module
Maps the GCP Pub/Sub schema back to the original Heka generic ingestion message

## Decoder Configuration Table -- optional
```lua
decoders_moz_ingest_gcp_ingestion = {
    -- validated_stream = false, -- default
}
```

## Functions

### decode

Decode and inject the generic ingestion pub/sub message

*Arguments*
- data (string) - gzipped json
- msg (string)  - pub/sub attributes

*Return*
- none, injects an error message on decode failure

--]]

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")

local inflate
local error     = error
local pcall     = pcall

local inject_message = inject_message

local Type = "error"
local cfg = read_config(module_cfg)
if type(cfg) == "table" then
    if cfg.validated_stream then
        inflate   = require "zlib".inflate
        Type = "validated"
    end
end


local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, msg)
    if not msg or not msg.Fields then error("schema\tno metadata", 0) end
    local fields = msg.Fields

    msg.Type                = Type
    msg.Logger              = fields.document_namespace ;fields.document_namespace = nil
    fields.docVersion       = fields.document_version   ;fields.document_version   = nil
    fields.docType          = fields.document_type      ;fields.document_type      = nil
    fields.documentId       = fields.document_id        ;fields.document_id        = nil
    fields.geoCity          = fields.geo_city           ;fields.geo_city           = nil
    fields.geoCountry       = fields.geo_country        ;fields.geo_country        = nil
    fields.geoSubdivision1  = fields.geo_subdivision1   ;fields.geo_subdivision1   = nil
    fields.geoSubdivision2  = fields.geo_subdivision2   ;fields.geo_subdivision2   = nil
    fields.Host             = fields.host               ;fields.host               = nil
    if Type == "validate" then
        fields.submission = inflate(31)(data)
    else
        if fields.error_type == "Duplicate" then
            msg.Type = "duplicate"
        else
            fields.DecodeErrorType  = fields.error_type
            fields.DecodeError      = fields.exception_class
            fields.DecodeErrorDetail= fields.error_message
        end
        fields.error_type           = nil
        fields.exception_class      = nil
        fields.error_message        = nil
        fields.stack_trace          = nil
        fields.stack_trace_cause_1  = nil
    end

    local ok, err = pcall(inject_message, msg)
    if not ok then
        error("inject_message\t" .. err, 0)
    end
end

return M
