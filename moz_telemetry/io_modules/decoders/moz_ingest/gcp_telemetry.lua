-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla GCP Decoder Module
Maps the GCP Pub/Sub schema back to the original Heka telemetry message

## Decoder Configuration Table (optional)
- none

## Functions

### decode

Decode and inject the message given as argument, using a module-internal stream reader

*Arguments*
- msg (string) - binary message to decode

*Return*
- none, injects an error message on decode failure

--]]

-- Imports
local random    = require "math".random
local string    = require "string"
local rjson     = require "rjson"
local inflate   = require "zlib".inflate
local dt        = require "lpeg.date_time"
local mtn       = require "moz_telemetry.normalize"
local error     = error
local ipairs    = ipairs
local pcall     = pcall
local type      = type
local tostring  = tostring

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local extract_payload_objects = {
    main = {
        "addonDetails",
        "addonHistograms",
        "childPayloads", -- only present with e10s
        "chromeHangs",
        "fileIOReports",
        "histograms",
        "info",
        "keyedHistograms",
        "lateWrites",
        "log",
        "simpleMeasurements",
        "slowSQL",
        "slowSQLstartup",
        "threadHangStats",
        "UIMeasurements",
        "gc",
        },
    }
extract_payload_objects["saved-session"] = extract_payload_objects["main"]

local environment_objects = {
    "addons",
    "build",
    "experiments",
    "partner",
    "profile",
    "settings",
    "system",
    }

local function remove_objects(msg, doc, section, objects)
    if type(objects) ~= "table" then return end

    local v = doc:find(section)
    if not v then return end

    for i, name in ipairs(objects) do
        local fieldname = string.format("%s.%s", section, name)
        msg.Fields[fieldname] = doc:make_field(doc:remove_shallow(v, name))
    end
end


local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
function decode(data, msg)
    if not msg or not msg.Fields then error("schema\tno metadata", 0) end
    local fields = msg.Fields
    local json = inflate(31)(data)
    local ok, err = pcall(doc.parse, doc, json, true)
    if not ok then
        error("json\tinvalid submission: %s" ..  err, 0)
    end

    msg.Type                    = "telemetry"
    msg.Logger                  = fields.document_namespace ;fields.document_namespace = nil
    fields.Date                 = fields.date               ;fields.date               = nil
    fields.docType              = fields.document_type      ;fields.document_type      = nil
    fields.documentId           = fields.document_id        ;fields.document_id        = nil
    fields.geoCity              = fields.geo_city           ;fields.geo_city           = nil
    fields.geoCountry           = fields.geo_country        ;fields.geo_country        = nil
    fields.geoSubdivision1      = fields.geo_subdivision1   ;fields.geo_subdivision1   = nil
    fields.geoSubdivision2      = fields.geo_subdivision2   ;fields.geo_subdivision2   = nil
    fields.Host                 = fields.host               ;fields.host               = nil
    fields.sampleId             = fields.sample_id          ;fields.sample_id          = nil
    fields.appName              = fields.app_name           ;fields.app_name           = nil
    fields.appBuildId           = fields.app_build_id       ;fields.app_build_id       = nil
    fields.appUpdateChannel     = fields.app_update_channel ;fields.app_update_channel = nil
    fields.normalizedChannel    = mtn.channel(fields.appUpdateChannel)
    fields.sourceVersion        = fields.document_version   ;fields.document_version   = nil
    if fields.submission_timestamp then
        local y, m, d = string.match(fields.submission_timestamp, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if y then fields.submissionDate   = y .. m .. d end
    end

    local rn = random(100)
    local keep_submission = ( -- sample to reduce drive I/O
        fields.normalizedChannel == "nightly"               -- 100% sample
        or (fields.normalizedChannel == "beta" and rn <= 10)-- ~10% random sample
        or rn == 50)                                        -- ~1% random sample

    if doc:value(doc:find("version")) then
        local cts = doc:value(doc:find("creationDate"))
        if cts then
            fields.creationTimestamp = dt.time_to_ns(dt.rfc3339:match(cts))
        end
        fields.reason               = doc:value(doc:find("payload", "info", "reason"))
        fields.os                   = doc:value(doc:find("environment", "system", "os", "name"))
        fields.telemetryEnabled     = doc:value(doc:find("environment", "settings", "telemetryEnabled"))
        fields.activeExperimentId   = doc:value(doc:find("environment", "addons", "activeExperiment", "id"))
        fields.clientId             = doc:value(doc:find("clientId"))
        fields.sourceVersion        = doc:value(doc:find("version"))
        fields.docType              = doc:value(doc:find("type"))
        local app = doc:find("application")
        fields.appName              = doc:value(doc:find(app, "name"))
        fields.appVersion           = doc:value(doc:find(app, "version"))
        fields.appBuildId           = doc:value(doc:find(app, "buildId"))
        fields.appUpdateChannel     = doc:value(doc:find(app, "channel"))
        fields.appVendor            = doc:value(doc:find(app, "vendor"))
        fields.normalizedOSVersion  = mtn.os_version(doc:value(doc:find("environment", "system", "os", "version")))
        if keep_submission then
            remove_objects(msg, doc, "environment", environment_objects)
            remove_objects(msg, doc, "payload", extract_payload_objects[msg.Fields.docType])
        end
    elseif doc:value(doc:find("v"))  then
        -- This is mobile ping ("core", "mobile-event", "mobile-metrics" or "focus-event")
        fields.sourceVersion        = tostring(doc:value(doc:find("v")))
        fields.normalizedOs         = mtn.mobile_os(doc:value(doc:find("os")))
        fields.normalizedAppName    = mtn.mobile_app_name(fields.appName)
    end

    if keep_submission then fields.submission = doc end
    ok, err = pcall(inject_message, msg)
    if not ok then
        error("inject_message\t" .. err, 0)
    end
end


return M
