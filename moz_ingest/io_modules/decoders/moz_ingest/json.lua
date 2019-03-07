-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry JSON Decoder Module

## Decoder Configuration Table
```lua
decoders_moz_ingest_json = {
    -- String used to specify the root namespace directory. The path should
    -- contain one directory for each namespace. Each namespace directory should
    -- contain one directory for each docType and the files in the directory
    -- must be named <docType>.<version>.schema.json. If the schema file is not
    -- found for a namespace/docType/version combination, an error is generated.
    namespace_path = "/mnt/work/mozilla-pipeline-schemas/schemas",

    -- array of namespace directories to ignore
    -- namespace_ignore = {"heka", "metadata", "pioneer-study", "telemetry"},

    -- Transform the User-Agent header into user_agent_browser, user_agent_version, user_agent_os.
    -- user_agent_transform = false, -- default

    -- Always preserve the User-Agent header if transform is enabled.
    -- user_agent_keep = false, -- default

    -- Only preserve the User-Agent header if transform is enabled and fails.
    -- user_agent_conditional = false, -- default

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


-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")

local clf    = require "lpeg.common_log_format"
local lfs    = require "lfs"
local miu    = require "moz_ingest.util"
local os     = require "os"
local rjson  = require "rjson"

local assert               = assert
local create_stream_reader = create_stream_reader
local error                = error
local inject_message       = inject_message
local pcall                = pcall
local print                = print
local read_config          = read_config
local type                 = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local cfg = read_config(module_cfg)
assert(type(cfg) == "table", module_cfg .. " must be a table")
assert(type(cfg.namespace_path) == "string", "namespace_path must be set")
if cfg.namespace_ignore == nil then
    cfg.namespace_ignore = {"heka", "metadata", "pioneer-study", "telemetry"}
end
assert(type(cfg.namespace_ignore) == "table", "namespace_ignore must be a table")


local function load_namespaces(path)
    local t = {}
    for dn in lfs.dir(path) do
        local fqdn = string.format("%s/%s", path, dn)
        local mode = lfs.attributes(fqdn, "mode")
        if mode == "directory" and not dn:match("^%.") and not cfg.namespace_ignore[dn] then
            t[dn] = miu.load_json_schemas(fqdn)
        end
    end
    return t
end
local namespaces = load_namespaces(cfg.namespace_path)

local timer_t       = 0
local modified_t    = 0
local reload_fn     = "/tmp/mozilla-pipeline-schemas.reload"
os.remove(reload_fn)

local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local submissionField = {value = doc, representation = "json"}
local function process_json(hsr, msg)
    local report
    local ok, err = pcall(doc.parse_message, doc, hsr, "Fields[content]", nil, nil, true)
    if not ok then
        error(string.format("json\tinvalid submission: %s", err), 0)
    end

    local schema = namespaces[msg.Logger]
    if schema then schema = schema[msg.Fields.docType] end
    if schema then schema = schema[msg.Fields.docVersion] end
    if schema then
        ok, err, report = doc:validate(schema)
    else
        err = "schema not found"
    end

    if err then
        err = string.format("json\tnamespace: %s schema: %s version: %d error: %s",
                            msg.Logger, msg.Fields.docType, msg.Fields.docVersion, err)
        if report then err = string.format("%s\t%s", err, report) end
        error(err, 0)
    end
    msg.Fields.submission = submissionField
end


function transform_message(hsr, msg)
    if not msg then
        msg = miu.new_message(hsr)
    end

    local time_t = os.time()
    if time_t - timer_t >= 60 then
        local m = lfs.attributes(reload_fn, "modification")
        if m and m ~= modified_t then
            namespaces = load_namespaces(cfg.namespace_path)
            print("namespace schemas reloaded")
            modified_t = m
        end
        timer_t = time_t
    end

    process_json(hsr, msg)

    -- Migrate the original message data after the validation (avoids Field duplication in the error message)
    msg.Hostname                = hsr:read_message("Hostname")
    msg.Fields.Host             = hsr:read_message("Fields[Host]")
    msg.Fields["User-Agent"]    = hsr:read_message("Fields[User-Agent]")

    if msg.Fields["User-Agent"] and cfg.user_agent_transform then
        msg.Fields.user_agent_browser,
        msg.Fields.user_agent_version,
        msg.Fields.user_agent_os = clf.normalize_user_agent(msg.Fields["User-Agent"])
        if not ((cfg.user_agent_conditional and not msg.Fields.user_agent_browser) or cfg.user_agent_keep) then
            msg.Fields["User-Agent"] = nil
        end
    end

    local ok, err = pcall(inject_message, msg)
    if not ok then
        error("inject_message\t" .. err, 0)
    end
end


local hsr = create_stream_reader("decoders.moz_ingest.json")
function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
