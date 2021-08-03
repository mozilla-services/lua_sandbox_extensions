-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Elasticsearch Common Encoder Utility Functions

## Encoder Configuration Table
```lua
encoders_elasticsearch_common = {
    -- Boolean flag, if true then any time interpolation (often used to generate the
    -- ElasticSeach index) will use the timestamp from the processed message rather
    -- than the system time.
    es_index_from_timestamp = false -- optional, default shown

    -- Elastic 7 and newer are moving to type-less documents (use `type_name = nil` or `_doc`)
    -- https://www.elastic.co/guide/en/elasticsearch/reference/7.x/removal-of-types.html
    es_version = 5 -- optional, default shown

    -- String to use as the `_index` key's value in the  generated JSON.
    -- Supports field interpolation as described below.
    index = "heka-%{%Y.%m.%d}" -- optional, default shown

    -- String to use as the `_type` key's value in the generated JSON.
    -- Supports field interpolation as described below.
    type_name = nil -- optional, default shown

    -- String to use as the `_id` key's value in the generated JSON.
    -- Supports field interpolation as described below.
    id = nil -- optional, default shown
}

```

## Functions

### bulkapi_index_json

Returns a simple JSON 'index' structure satisfying the [ElasticSearch BulkAPI](http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/docs-bulk.html)

*Arguments*
* index (string or nil) - Used as the `_index` key's value in the generated JSON
  or nil to omit the key. Supports field interpolation as described below.
* type_name (string or nil) - Used as the `_type` key's value in the generated
  JSON or nil to omit the key. Supports field interpolation as described below.
* id (string or nil) - Used as the `_id` key's value in the generated JSON or
  nil to omit the key. Supports field interpolation as described below.
* ns (number or nil) - Nanosecond timestamp to use for any strftime field
  interpolation into the above fields. Current system time will be used if nil.

*Return*
* JSON - String suitable for use as ElasticSearch BulkAPI index directive.

*See*
[Field Interpolation](/heka/modules/heka/msg_interpolate.md)

### load_encoder_cfg

Loads and validates the common Elastic Search encoder configuration options.

*Arguments*
* none

*Return*
* cfg (table)
--]]

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")

local cjson         = require "cjson"
local mi            = require "heka.msg_interpolate"
local assert        = assert
local type          = type
local read_message  = read_message
local read_config   = read_config

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local result_inner = {
    _index = nil,
    _type = nil,
    _id = nil
}

--[[ Public Interface --]]

function bulkapi_index_json(index, type_name, id, ns)
    local secs
    if ns then
        secs = ns / 1e9
    end
    if index then
        result_inner._index = string.lower(mi.interpolate(index, secs))
    else
        result_inner._index = nil
    end
    if type_name then
        result_inner._type = mi.interpolate(type_name, secs)
    else
        result_inner._type = nil
    end
    if id then
        result_inner._id = mi.interpolate(id, secs)
    else
        result_inner._id = nil
    end
    return cjson.encode({index = result_inner})
end


function load_encoder_cfg()
    local cfg = read_config(module_cfg)
    assert(type(cfg) == "table", module_cfg .. " must be a table")

    if cfg.es_index_from_timestamp == nil then
        cfg.es_index_from_timestamp = false
    else
        assert(type(cfg.es_index_from_timestamp) == "boolean",
               "es_index_from_timestamp must be nil or boolean")
    end

    if cfg.index == nil then
        cfg.index = "heka-%{%Y.%m.%d}"
    else
        assert(type(cfg.index) == "string", "index must be nil or a string")
    end

    if cfg.type_name == nil then
      if cfg.es_version < 7 then
        cfg.type_name = "message"
      else
        assert(cfg.type_name == "_doc", "type_name must be nil or _doc, types are deprecated since Elasic 7.0")
      end
    else
        assert(type(cfg.type_name) == "string", "type_name must be nil or a string")
    end

    return cfg
end

return M
