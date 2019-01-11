-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Mobile Monitor

Monitors the various mobile applications for ingestion errors and inactivity,
partitioned by normalizedAppName, normalizedOs, docType

* ingestion_error - monitors the ingestion error rate
* volume - monitors for inactivity (no data)

## Sample Configuration
```lua
filename = 'moz_telemetry_mobile_monitor.lua'
message_matcher = "Fields[normalizedChannel] == 'release' && (" ..
    "Fields[docType] == 'core'" ..
" || Fields[docType] == 'mobile-event'" ..
" || Fields[docType] == 'focus-event'" ..
" || Fields[docType] == 'mobile-metrics'" ..
") && (Type == 'telemetry' || Type == 'telemetry.error')"

ticker_interval = 60
preserve_data = true
timer_event_inject_limit = 1000

alert = {
  -- disabled = false,
  prefix = true,
  -- throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = { -- map of normalizedAppName, normalizedOs, docType
--  Fennec = {
--    Android = {
--      core = {
--        ingestion_error = 0.1, -- percent error (0.0 - 100.0, nil disables)
--        volume          = 5,   -- inactivity timeout in minutes (0 - 60, 0 == auto scale, nil disables)
--      },
--    }
--  },
    ["*"] = {
      ["*"] = {
        ["*"] = {
          ingestion_error = 1,
          volume          = 0,
        },
      }
    }
  }
}
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0
data = {}

require "math"
require "string"
require "table"

local sats  = require "streaming_algorithms.time_series"
local p2    = require "streaming_algorithms.p2"
local alert = require "heka.alert"
local mtn   = require "moz_telemetry.normalize"

local SEC_IN_MINUTE     = 60
local TS_ROWS           = 61
local thresholds        = alert.thresholds

local function validate_thresholds()
    for nap, app in pairs(thresholds) do
        for nos, os in pairs(app) do
            for dt, cfg in pairs(os) do
                for k, arg in pairs(cfg) do
                    if k == "volume" then
                        assert(type(arg) == "number" and arg >= 0 and arg <= 60,
                               string.format("%s->%s->%s: %s alert must contain a numeric timeout (0-60 minutes)", nap, nos, dt, k))
                    elseif k == "ingestion_error" then
                        assert(type(arg) == "number" and arg >= 0 and arg <= 100,
                               string.format("%s->%s->%s: %s alert must contain a numeric percent (0-100)", nap, nos, dt, k))
                    else
                        error("invalid alert type " .. k)
                    end
                    setmetatable(cfg, {}) -- prevent preservation when referenced from global 'data'
                end
                if dt == "*" then
                    setmetatable(os, {__index = function() return cfg end})
                end
            end
            if nos == "*" then
                setmetatable(app, {__index = function() return os end})
            end
        end
        if nap == "*" then
            setmetatable(thresholds, {__index = function() return app end})
        end
    end
end
validate_thresholds()


local function get_data(ns, nap, nos, dt)
    local app = data[nap]
    if not app then
        app = {}
        data[nap] = app
    end

    local os = app[nos]
    if not os then
        os = {}
        app[nos] = os
    end

    local d = os[dt]
    if not d then
        local tcfg = thresholds[nap]
        if tcfg then tcfg = tcfg[nos] end
        if tcfg then tcfg = tcfg[dt] end
        d = {
            errors      = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9), -- error count
            volume      = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9), -- success count
            created     = ns,
            gapc        = 0, -- count of the gap between data rows
            gapq        = p2.quantile(0.99),
            diagnostics = {}, -- error message analysis
            tcfg        = tcfg, -- alerting threshold configuration
            }
        os[dt] = d
    end
    return d
end


local function diagnostic_update(ns, diag)
    local de = read_message("Fields[DecodeError]") or "<none>"
    local ts = diag[de]
    if not ts then
        ts = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9)
        diag[de] = ts
    end
    ts:add(ns, 1)
end


function process_message()
    local nap   = mtn.mobile_app_name(read_message("Fields[appName]"))
    local nos   = read_message("Fields[normalizedOs]") or "Other"
    local dt    = read_message("Fields[docType]")
    local ns    = read_message("Timestamp")
    local mtype = read_message("Type")

    local d = get_data(ns, nap, nos, dt)
    if mtype == "telemetry" then
        d.volume:add(ns, 1)
    elseif mtype == "telemetry.error" then
        d.errors:add(ns, 1)
        diagnostic_update(ns, d.diagnostics)
    end
    return 0
end


local function diagnostic_prune(ns, diag)
    for k, v in pairs(diag) do
        if not v:get(ns) then v:add(ns, 0) end
        local _, cnt = v:stats(nil, TS_ROWS)
        if cnt == 0 then diag[k] = nil end
    end
end


local ingestion_volume_template = [[
%s - No new valid data has been seen in %d minutes

Stats for the last %d minutes
=============================
Submissions       : %d
Minutes with data : %d
Quantile data gap : %g
]]
local function alert_check_volume(name, d, ns, vsum, vcnt, gap)
    local iato = d.tcfg.volume
    if not iato
    or vcnt == 0
    or ns - d.created <= TS_ROWS * 60e9
    or alert.throttled(name) then
        return false
    end

    if iato == 0 then
        if gap ~= gap then return end -- NaN, no estimate yet
        iato = math.ceil((gap + 1) * 5)
        if iato >= TS_ROWS then return end -- data is too sporadic, don't monitor
    end

    local ct = d.volume:current_time()
    local sum, cnt = d.volume:stats(ct - iato * 60e9, iato + 1) -- include the current active minute
    if cnt == 0 then
        if alert.send(name, "inactivity timeout",
                      string.format(ingestion_volume_template,
                                    name, iato, TS_ROWS, vsum, vcnt, gap)) then
            return true
        end
    end
    return false
end


local function diagnostic_dump(diag)
    local t   = {}
    local idx = 0
    for k, v in pairs(diag) do
        local sum, _ = v:stats(nil, TS_ROWS)
        idx = idx + 1
        t[idx] = string.format("%d\t%s", sum, k)
    end
    table.sort(t, function(a, b) return tonumber(a:match("^%d+")) > tonumber(b:match("^%d+")) end)
    return table.concat(t, "\n")
end


local ingestion_error_template = [[
Ingestion Data for the Last Hour
================================
valid            : %d
error            : %d
percent_error    : %g
max_percent_error: %g

Diagnostic (count/error)
========================
%s
]]
local function alert_check_ingestion_error(name, d, vsum, esum)
    if vsum < 1000 and esum < 1000 then return false end
    local mpe = d.tcfg.ingestion_error
    if not mpe or alert.throttled(name) then return false end

    local pe  = esum / (vsum + esum) * 100
    if pe > mpe then
        if alert.send(name, "ingestion error",
                      string.format(ingestion_error_template, vsum, esum, pe, mpe,
                                    diagnostic_dump(d.diagnostics))) then
            return true
        end
    end
    return false
end


function timer_event(ns, shutdown)
    if shutdown then return end

    local summary = {"App\tOs\tdocType\tSubmissions\tSubmissions Active Minutes\tSubmissions Current Data Gap\tSubmissions Quantile Data Gap\tErrors\tErrors Active Minutes"}
    local cnt = 1
    for nap, app in pairs(data) do
        for nos, os in pairs(app) do
            for dt, d in pairs(os) do
                -- always advance the time series buffers
                if not d.volume:get(ns) then
                    d.volume:add(ns, 0)
                    d.gapc = d.gapc + 1
                else
                    for i=0, d.gapc do
                        d.gapq:add(i)
                    end
                    d.gapc = 0
                end
                if not d.errors:get(ns) then d.errors:add(ns, 0) end
                diagnostic_prune(ns, d.diagnostics)

                local vsum, vcnt = d.volume:stats(nil, TS_ROWS)
                local esum, ecnt = d.errors:stats(nil, TS_ROWS)
                local gap = d.gapq:estimate(2)
                cnt = cnt + 1
                summary[cnt] = string.format("%s\t%s\t%s\t%d\t%d\t%d\t%g\t%d\t%d",
                                             nap, nos, dt, vsum, vcnt,
                                             d.gapc, gap, esum, ecnt)
                if d.tcfg then
                    local name = nap .. "_" .. nos .. "_" .. dt
                    alert_check_volume(name, d, ns, vsum, vcnt, gap)
                    alert_check_ingestion_error(name, d, vsum, esum)
                end
            end
        end
    end
    inject_payload("tsv", "summary", table.concat(summary, "\n"))
end
