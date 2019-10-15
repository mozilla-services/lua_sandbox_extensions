-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster Worker Metrics Decoder Module.
Parses the Taskcluster Papertrail WORKER_METRICS logs

## Decoder Configuration Table
decoders_taskcluster_work_metrics = {
    -- taskcluster_schema_path = "/usr/share/luasandbox/schemas/taskcluster" -- default
}

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Data to write to the msg.Payload
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on inject_message failure.

--]]

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")
local cfg           = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
cfg.taskcluster_schema_path = cfg.task_cluster_schema_path or "/usr/share/luasandbox/schemas/taskcluster"

local cjson     = require "cjson"
local rjson     = require "rjson"
local date      = require "date"
local io        = require "io"
local sdu       = require "lpeg.sub_decoder_util"
local string    = require "string"

local assert         = assert
local inject_message = inject_message
local read_config    = read_config

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local worker_metrics_schema_file = cfg.taskcluster_schema_path .. "/worker_metrics.1.schema.json"
local fh = assert(io.open(worker_metrics_schema_file, "r"))
local worker_metrics_schema = fh:read("*a")
worker_metrics_schema = rjson.parse_schema(worker_metrics_schema)
fh:close()

local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC

function decode(data, dh, mutable)
    local payload = data:match("WORKER_METRICS[^{]*(.+)")
    if not payload then return end

    doc:parse(payload)
    local ok, err, report = doc:validate(worker_metrics_schema)
    if not err then
        local fields     = cjson.decode(payload)
        fields.timestamp = date.format(fields.timestamp * 1e9, "%Y-%m-%dT%H:%M:%SZ")

        local msg   = sdu.copy_message(dh, false)
        msg.Type    = "worker_metrics"
        msg.Payload = cjson.encode(fields)
        inject_message(msg)
    else
        local msg = {
            Type = "error.worker_metrics.validation",
            Payload = err,
            Fields = {
                schema  = worker_metrics_schema_file,
                detail  = report,
                data    = payload
            }
        }
        inject_message(msg)
    end
end


return M
