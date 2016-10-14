-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Elasticsearch Encoder for Heka Messages

## Encoder Configuration Table

[Common Options](common.html)

## Functions

### encode

Creates the ElasticSearch bulk API index JSON and combines it with the
pre-formatted JSON from the message payload (a new line is added if necessary).

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
local decode_message = decode_message
local read_message   = read_message
local pcall          = pcall
local ipairs         = ipairs
local cfg            = es.load_encoder_cfg()
local getn           = require "table".getn
local date           = require "os".date

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function encode()
--  local msg = decode_message(read_message("raw"))

    local ns
    if cfg.es_index_from_timestamp then ns = read_message("Timestamp") end
    local idx_json = es.bulkapi_index_json(cfg.index, cfg.type_name, cfg.id, ns)

    local tbl = {}

    tbl.Timestamp  = date("!%Y-%m-%dT%XZ", ns and ns / 1e9)
    tbl.Type       = read_message("Type")
    tbl.Hostname   = read_message("Hostname")
    tbl.Pid        = read_message("Pid")
    tbl.Logger     = read_message("Logger")
    tbl.EnvVersion = read_message("EnvVersion")
    tbl.Severity   = read_message("Severity")
    tbl.Payload   = read_message("Payload")
--  Uuid is not valid json
    local msg = decode_message(read_message("raw"))
    if msg.Fields then
        for i, field in ipairs(msg.Fields) do
            tbl[field.name] = read_message("Fields["..field.name.."]")
        end
    end
    local ok, data = pcall(cjson.encode, tbl)
    return string.format("%s\n%s\n", idx_json, data)
end

return M
