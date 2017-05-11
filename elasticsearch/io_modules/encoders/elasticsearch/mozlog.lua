-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Elasticsearch Encoder for Heka Messages

## Encoder Configuration Table

[Common Options](common.md)

## Functions

### encode

Creates the ElasticSearch bulk API index JSON and combines it with the
JSON created by iterating the Heka message Fields.

*Arguments*
- none

*Return*
- JSON (string, nil) Elasticsearch JSON or nil (skip no payload)

## Sample Output
```json
{"index":{"_index":"mylogger-2014.06.05","_type":"mytype-host.domain.com"}}
{"json":"data","extracted":"from","heka":"message"}
```
--]]

-- Imports
local cjson          = require "cjson"
local string         = require "string"
local es             = require "encoders.elasticsearch.common"
local mi             = require "heka.msg_interpolate"
local decode_message = decode_message
local read_message   = read_message
local pcall          = pcall
local ipairs         = ipairs
local cfg            = es.load_encoder_cfg()

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function encode()
    local tbl = decode_message(read_message("raw"))

    local ns
    if cfg.es_index_from_timestamp then ns = tbl.Timestamp end
    local idx_json = es.bulkapi_index_json(cfg.index, cfg.type_name, cfg.id, ns)

    tbl.Timestamp = mi.get_timestamp_ms(ns)
    tbl.Uuid = mi.get_uuid(tbl.Uuid)
    if tbl.Fields then
        for i, field in ipairs(tbl.Fields) do
            if #field.value == 1 then
                tbl[field.name] = field.value[1]
            else
                tbl[field.name] = field.value
            end
        end
        tbl.Fields = nil
    end
    local ok, data = pcall(cjson.encode, tbl)
    return string.format("%s\n%s\n", idx_json, data)
end

return M
