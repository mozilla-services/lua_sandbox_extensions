-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.
--[[
# Mozilla Ingestion Document Type Bootstrapper

Starts a new monitor plugin every time a new docType is detected

## Sample Configuration
```lua
filename        = "moz_ingest_doctype_bootstrap.lua"
message_matcher = "Fields[docType] =~ '^[-a-zA-Z0-9]+$' && Logger =~ '^[-a-zA-Z0-9]+$'"
ticker_interval = 600
preserve_data   = true

minimum_submissions = 10 -- minimum submissions in a day before starting a new plugin
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0
doctypes = {}

require "io"
require "os"
require "string"

local min_sub   = read_config("minimum_submissions") or 10
local sblp      = read_config("sandbox_load_path")
local sbrp      = read_config("sandbox_run_path")

local telemetry_threshold_default = [[
    ["*"] = {
      ingestion_error = 1.0, -- percent error (0.0 - 100.0, nil disables)
      duplicates      = nil, -- percent error (0.0 - 100.0, nil disables)
      inactivity      = 0, -- inactivity timeout in minutes (0 - 60, 0 == auto scale, nil disables)
      capture_samples = 2, -- number of samples to capture (1-10, nil disables)
    }
]]

local telemetry_thresholds = {
    ["saved-session"] = '["*"] = {} -- disable everything'
}
setmetatable(telemetry_thresholds, {__index = function(t, k) return telemetry_threshold_default end });

local telemetry_tmpl = [[
filename        = "moz_ingest_doctype_monitor.lua"
docType         = "%s"
message_matcher = "Fields[docType] == '" .. docType .. "' && Logger == '%s' && Fields[appName] == 'Firefox'"
ticker_interval = 60
preserve_data   = true
output_limit    = 1024 * 1024 * 8
memory_limit    = 1024 * 1024 * 64
telemetry       = true
hierarchy       = {
    {module="moz_telemetry.normalize", func="channel", field="Fields[appUpdateChannel]"},
}

alert = {
  -- disabled = false,
  prefix = true,
  -- throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },

  thresholds = { -- map of hierarchy specified above
    ["aurora"] = {},
    ["Other"] = {},
    %s
  }
}
preservation_version = 0 -- if the hierarchy is changed this must be incremented
]]


local mobile_telemetry = {
    ["core"]            = true,
    ["mobile-event"]    = true,
    ["focus-event"]     = true,
    ["mobile-metrics"]  = true,
}

local mobile_tmpl = [[
filename        = "moz_ingest_doctype_monitor.lua"
docType         = "%s"
message_matcher = "Fields[docType] == '" .. docType .. "' && Logger == '%s'"
ticker_interval = 60
preserve_data   = true
output_limit    = 1024 * 1024 * 8
memory_limit    = 1024 * 1024 * 64
timer_event_inject_limit  = 1000
telemetry       = true
hierarchy       = {
    {module="moz_telemetry.normalize", func="mobile_app_name", field="Fields[appName]"},
    {module="moz_telemetry.normalize", func="channel", field="Fields[appUpdateChannel]"},
}

alert = {
  -- disabled = false,
  prefix = true,
  -- throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },

  thresholds = { -- map of hierarchy specified above
    ["*"] = {
      ["Other"] = {},
      ["*"] = {
        ingestion_error = 1.0, -- percent error (0.0 - 100.0, nil disables)
        duplicates      = nil, -- percent error (0.0 - 100.0, nil disables)
        inactivity      = 0, -- inactivity timeout in minutes (0 - 60, 0 == auto scale, nil disables)
        capture_samples = 1, -- number of samples to capture (1-10, nil disables)
      }
    }
  }
}
preservation_version = 0 -- if the hierarchy is changed this must be incremented
]]



local ingestion_tmpl = [[
filename        = "moz_ingest_doctype_monitor.lua"
docType         = "%s"
message_matcher = "Fields[docType] == '" .. docType .. "' && Logger == '%s'"
ticker_interval = 60
preserve_data   = true
output_limit    = 1024 * 1024 * 8
memory_limit    = 1024 * 1024 * 64
hierarchy       = nil

alert = {
  -- disabled = false,
  prefix = true,
  -- throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },

  thresholds = { -- map of hierarchy specified above
    ingestion_error = 1.0, -- percent error (0.0 - 100.0, nil disables)
    duplicates      = nil, -- percent error (0.0 - 100.0, nil disables)
    inactivity      = 0, -- inactivity timeout in minutes (0 - 60, 0 == auto scale, nil disables)
    capture_samples = 10, -- number of samples to capture (1-10, nil disables)
  }
}
preservation_version = 0 -- if the hierarchy is changed this must be incremented
]]

local fn_tmpl = "%s/analysis/dl.dt_%s_%s.%s"
local function start_monitor(namespace, dt)
    local cfg
    if namespace ~= "telemetry" then
        cfg = string.format(ingestion_tmpl, dt, namespace)
    else
        if mobile_telemetry[dt] then
            cfg = string.format(mobile_tmpl, dt, namespace)
        else
            cfg = string.format(telemetry_tmpl, dt, namespace, telemetry_thresholds[dt])
        end
    end
    local fn = string.format(fn_tmpl, sblp, namespace, dt, "cfg")

    local fh = io.open(fn, "w")
    if fh then
        fh:write(cfg)
        fh:close()
    end
end


function process_message()
    local ns = read_message("Timestamp")
    local namespace = read_message("Logger")
    local dt = read_message("Fields[docType]")
    local nst = doctypes[namespace]
    if not nst then
        nst = {}
        doctypes[namespace] = nst
    end
    local t = nst[dt]
    if not t then
        t = {ns = ns, cnt = 1}
        nst[dt] = t
    else
        local cnt = t.cnt + 1
        t.ns = ns
        t.cnt = cnt
        if cnt == min_sub then
            start_monitor(namespace, dt)
        end
    end
    return 0
end


function timer_event(ns, shutdown)
    for namespace, nst in pairs(doctypes) do
        for dt, t in pairs(nst) do
            if t.off then
                local fn = string.format(fn_tmpl, sbrp, namespace, dt, "off")
                os.remove(fn)
                nst[dt] = nil
            elseif ns - t.ns >= 86400e9 then
                if t.cnt < min_sub then
                    nst[dt] = nil
                else
                    local fn = string.format(fn_tmpl, sblp, namespace, dt, "off")
                        local fh = io.open(fn, "w")
                    if fh then
                        fh:write("")
                        fh:close()
                    end
                    t.off = true
                end
            end
        end
    end
end
