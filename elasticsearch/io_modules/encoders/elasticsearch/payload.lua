-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Elasticsearch Encoder for Heka Payload-only Messages

The message payload must be pre-formatted JSON in an ElasticSearch compatible
format.

## Encoder Configuration Table

[Common Options](common.md)

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
{"json":"data","extracted":"from","message":"payload"}
```
--]]

-- Imports
local string        = require "string"
local es            = require "encoders.elasticsearch.common"
local read_message  = read_message
local cfg           = es.load_encoder_cfg()

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function encode()
    local payload = read_message("Payload")
    if not payload then return nil end

    local ns
    if cfg.es_index_from_timestamp then ns = read_message("Timestamp") end
    local idx_json = es.bulkapi_index_json(cfg.index, cfg.type_name, cfg.id, ns)
    if string.match(payload, "\n$", -1) then
        return string.format("%s\n%s", idx_json, payload)
    end
    return string.format("%s\n%s\n", idx_json, payload)
end

return M
