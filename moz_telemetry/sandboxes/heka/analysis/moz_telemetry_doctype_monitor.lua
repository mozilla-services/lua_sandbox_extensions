
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry docType Monitor

Monitors a specific docType for volume, shape, size, duplicate, ingestion_error
and latency issues by normalized channel name.

* volume - monitors for inactivity (no data) and optionally a percent change in
  the number of submissions compared to the same 24 hour time period of the
  previous week

* shape - SAX analysis comparing the same 24 hour time period of the previous
  week for a shape exceeding the configured mindist

* size - monitors the previous 24 hours for a percent change in the average
  submission size compared to the configured value

* duplicate - monitors the previous 24 hours for a duplicate rate exceeding
  the configured value

* ingestion_error - monitors the last hour for an ingestion error rate
  exceeding the configured value

* latency - monitors a one hour tumbling window of latency distributions where
  X% of submissions are not greater than Y hours latent

## Sample Configuration
```lua
filename = 'moz_telemetry_doctype_monitor.lua'
docType = "main"
message_matcher = 'Fields[docType] == "'.. docType .. '" && (Type == "telemetry" || Type == "telemetry.error"  || Type == "telemetry.duplicate")'
ticker_interval = 60
preserve_data = true

alert = {
  disabled = false,
  prefix = true,
  throttle = 1440, -- default to once a day (inactivity and ingestion_error default to 90)
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },

  thresholds = { -- map of normalized channel names
    release = {
      volume = {
        inactivity_timeout = 5, -- minutes
        percent_delta = 10, -- optional
      },
      size = {
        average = 15529, -- bytes
        percent_delta = 10,
      },
      ingestion_error = {
        percent = 0.5,
      },
      duplicate = {
        percent = 2,
      },
      shape = {
        mindist = 0,
      },
      latency = {
        hours = 24,     -- 1 - 192
                        -- everything in the future is added to the first bucket
                        -- everything in the past is added to the last bucket
        percent = 33,   -- alerts if more than 33% of submission are greater than 24 hours latent
      }
    }
  }
}
```
--]]
_PRESERVATION_VERSION = 0

require "circular_buffer"
require "math"
require "os"
require "sax"
require "string"
local alert = require "heka.alert"
local mtn   = require "moz_telemetry.normalize"
local stats = require "lsb.stats"

local SAX_CARDINALITY   = 6
local SEC_IN_MINUTE     = 60
local HOURS_IN_DAY      = 24
local HOURS_IN_WEEK     = 168
local MINS_IN_HOUR      = 60
local SEC_IN_HOUR       = SEC_IN_MINUTE * MINS_IN_HOUR
local MINS_IN_DAY       = MINS_IN_HOUR * HOURS_IN_DAY
local ROWS              = MINS_IN_DAY * 8 + 1 -- add an extra row to compensate for the currently active minute
local DEFAULT_CHANNEL   = mtn.get_channel_name()
local CHANNEL_CNT       = mtn.get_channel_count()

local thresholds    = read_config("alert").thresholds
local docType       = read_config("docType") or error("docType is required")
local hwin          = sax.window.new(MINS_IN_DAY, HOURS_IN_DAY, SAX_CARDINALITY)
local cwin          = sax.window.new(MINS_IN_DAY, HOURS_IN_DAY, SAX_CARDINALITY)

local channels      = {}
for i = 0, CHANNEL_CNT - 1 do
    local name = mtn.get_channel_name(i)
    channels[name] = i + 1
end


local function create_cb(rows, spr, unit)
    local cb = circular_buffer.new(rows, CHANNEL_CNT, spr)
    for channel, col in pairs(channels) do
        cb:set_header(col, channel, unit)
    end
    return cb
end

volume          = create_cb(ROWS, SEC_IN_MINUTE)
size            = create_cb(ROWS, SEC_IN_MINUTE, "B")
ingestion_error = create_cb(ROWS, SEC_IN_MINUTE)
diagnostics     = {}
duplicate       = create_cb(ROWS, SEC_IN_MINUTE)
latency         = create_cb(HOURS_IN_DAY * 8, SEC_IN_HOUR) -- tumbling window
latency_cnt     = 0

local function latency_clear()
    if latency_cnt >= MINS_IN_HOUR then
        latency_cnt = 0
        latency = create_cb(HOURS_IN_DAY * 8, SEC_IN_HOUR) -- recreate
    end
end


local function diagnostic_update(ns, diag)
    if not diag then return end

    local de = read_message("Fields[DecodeError]") or "<none>"
    local cb = diag[de]
    if not cb then
        cb = circular_buffer.new(MINS_IN_HOUR + 1, 1, SEC_IN_MINUTE)
        diag[de] = cb
    end
    cb:add(ns, 1, 1)
end


function process_message()
    local ns = read_message("Timestamp")
    local channel = mtn.channel(read_message("Fields[appUpdateChannel]"))
    local col = channels[channel]
    if not col then
        col = 1
        channel = DEFAULT_CHANNEL
    end

    local mtype = read_message("Type")
    if mtype == "telemetry" then
        volume:add(ns, col, 1)
        size:add(ns, col, read_message("size"))
        local cns = read_message("Fields[creationTimestamp]") or ns
        local delta = ns - cns
        if delta < 0 then delta = 0 end
        if delta >= 3600e9 * 192 then delta = 3600e9 * (192 - 1) end
        latency:add(delta, col, 1)
    elseif mtype == "telemetry.error" then
        ingestion_error:add(ns, col, 1)
        diagnostic_update(ns, diagnostics[channel])
    elseif mtype == "telemetry.duplicate" then
        duplicate:add(ns, col, 1)
    end
    return 0
end


local args = {
    col     = 0,
    hour    = {s =  0, e = 0, array = nil, sum = 0, cnt = 0},
    day     = {s =  0, e = 0, array = nil, sum = 0, cnt = 0},
    hday    = {s =  0, e = 0, array = nil, sum = 0, cnt = 0},
}


local function get_array(col, t)
    t.array = volume:get_range(col, t.s, t.e)
    t.sum, t.cnt = stats.sum(t.array)
end


function timer_event(ns, shutdown)
    -- always advance the buffer/graphs
    if not volume:get(ns, 1) then volume:add(ns, 1, 0/0) end
    if not size:get(ns, 1) then size:add(ns, 1, 0/0) end
    if not ingestion_error:get(ns, 1) then ingestion_error:add(ns, 1, 0/0) end
    if not duplicate:get(ns, 1) then duplicate:add(ns, 1, 0/0) end

    args.day.e  = volume:current_time() - 60e9 -- exclude the current minute
    args.hour.e = args.day.e
    args.hday.e = args.day.e - MINS_IN_DAY * 60e9 * 7

    args.day.s  = args.day.e - ((MINS_IN_DAY - 1) * 60e9)
    args.hour.s = args.hour.e - ((MINS_IN_HOUR - 1) * 60e9)
    args.hday.s = args.day.s - MINS_IN_DAY * 60e9 * 7

    for channel, ccfg in pairs(thresholds) do
        args.col = channels[channel]
        get_array(args.col, args.hour)
        for at, cfg in pairs(ccfg) do
            cfg._fp(ns, channel, cfg, args)
        end
        args.hour.array = nil
        args.day.array  = nil
        args.hday.array = nil
    end
    inject_payload("cbuf", "volume" , volume)
    inject_payload("cbuf", "size"   , size)
    inject_payload("cbuf", "ingestion_error" , ingestion_error)
    inject_payload("cbuf", "duplicate" , duplicate)
    inject_payload("cbuf", "latency" , latency)
    latency_clear()
end


local function alert_check_volume(ns, channel, cfg, args)
    if args.hour.cnt == 0 or alert.throttled(channel, 90) then return false end

    local iato = cfg.inactivity_timeout
    if MINS_IN_HOUR - args.hour.cnt > iato then
        local _, cnt = stats.sum(volume:get_range(args.col, args.hour.e - ((iato - 1) * 60e9))) -- include the current minute
        if cnt == 0 then
            if alert.send(channel, "inactivitiy timeout",
                          string.format("No new valid data has been seen in %d minutes\n\ngraph: %s\n",
                                        iato, alert.get_dashboard_uri("volume")), 90) then
                volume:annotate(ns, args.col, "alert", "inactivitiy timeout")
                return true
            end
        end
    end

    if not cfg.percent_delta then return false end
    local sv = volume:get(args.hday.s, args.col)
    if sv ~= sv then return false end -- no historical data yet

    if not args.day.array then get_array(args.col, args.day) end
    if not args.hday.array then get_array(args.col, args.hday) end
    local delta = (args.day.sum - args.hday.sum) / args.hday.sum * 100
    if math.abs(delta) > cfg.percent_delta then
        if alert.send(channel, "volume",
                      string.format("historical: %d current: %d  delta: %g%%\n\ngraph: %s\n",
                                    args.hday.sum, args.day.sum, delta, alert.get_dashboard_uri("volume"))) then
            volume:annotate(ns, args.col, "alert", string.format("volume %.4g%%", delta))
            return true
        end
    end
    return false
end


local function alert_check_size(ns, channel, cfg, args)
    if not args.day.array then get_array(args.col, args.day) end
    if args.day.sum < 24000 or alert.throttled(channel) then return false end

    local sum, cnt = stats.sum(size:get_range(args.col, args.day.s, args.day.e))
    local avg = sum/args.day.sum
    local delta = (avg - cfg.average) / cfg.average * 100
    if math.abs(delta) > cfg.percent_delta then
        if alert.send(channel, "size",
                      string.format("The average message size has changed by %g%% (current avg: %dB)\n\ngraph: %s\n",
                                    delta, avg, alert.get_dashboard_uri("size"))) then
            size:annotate(ns, args.col, "alert", string.format("%.4g%%", delta))
            return true
        end
    end
    return false
end


local function diagnostic_dump(e, diag)
    local t   = {}
    local idx = 0
    for k, v in pairs(diag) do
        local val, _ = stats.sum(v:get_range(1, nil, e))
        idx = idx + 1
        t[idx] = string.format("%d\t%s", val, k)
    end
    table.sort(t, function(a, b) return tonumber(a:match("^%d+")) > tonumber(b:match("^%d+")) end)
    return table.concat(t, "\n")
end


local function diagnostic_prune(ns, diag)
    for k, v in pairs(diag) do
        if not v:get(ns, 1) then
            v:add(ns, 1, 0/0) -- always advance the buffer
        end
        local _, cnt = stats.sum(v:get_range(1))
        if cnt == 0 then diag[k] = nil end
    end
end


local ingestion_error_template = [[
Ingestion Data for the Last Hour
================================
valid            : %d
error            : %d
percent_error    : %g
max_percent_error: %g

graph: %s

Diagnostic (count/error)
========================
%s
]]
local function alert_check_ingestion_error(ns, channel, cfg, args)
    diagnostic_prune(ns, diagnostics[channel])
    if alert.throttled(channel, 90) then return false end

    local err = stats.sum(ingestion_error:get_range(args.col, args.hour.s, args.hour.e))
    if args.hour.sum < 1000 and err < 1000 then return false end

    local mpe = cfg.percent
    local pe  = err / (args.hour.sum + err) * 100
    if pe > mpe then
        if alert.send(channel, "ingestion error",
                      string.format(ingestion_error_template, args.hour.sum, err, pe, mpe,
                                    alert.get_dashboard_uri("ingestion_error"),
                                    diagnostic_dump(end_t, diagnostics[channel])), 90) then
            ingestion_error:annotate(ns, args.col, "alert", string.format("%.4g%%", pe))
            return true
        end
    end
    return false
end


local duplicate_template = [[
Duplicate Data for the Last Hour
================================
unique               : %d
duplicate            : %d
percent_duplicate    : %g
max_percent_duplicate: %g

graph: %s
]]
local function alert_check_duplicate(ns, channel, cfg, args)
    if not args.day.array then get_array(args.col, args.day) end
    if alert.throttled(channel) then return false end

    local dupes = stats.sum(duplicate:get_range(args.col, args.day.s, args.day.e))
    if args.day.sum < 24000 and dupes < 24000 then return false end

    local mde = cfg.percent
    local de  = dupes / (args.day.sum + dupes) * 100
    if de > mde then
        if alert.send(channel, "duplicate",
                      string.format(duplicate_template, args.day.sum, dupes, de, mde,
                                    alert.get_dashboard_uri("duplicate"))) then
            duplicate:annotate(ns, args.col, "alert", string.format("%.4g%%", de))
            return true
        end
    end
    return false
end


local shape_template = [[
SAX Analysis
============
start time : %s
end time   : %s
current    : %s
historical : %s
mindist    : %g
max_mindist: %g

graph: %s
]]
local function alert_check_shape(ns, channel, cfg, args)
    if alert.throttled(channel) then return false end

    local sv = volume:get(args.hday.s, args.col)
    if sv ~= sv then return false end -- no historical data yet

    if not args.day.array then get_array(args.col, args.day) end
    if not args.hday.array then get_array(args.col, args.hday) end
    cwin:add(args.day.array)
    hwin:add(args.hday.array)

    local mindist    = sax.mindist(hwin, cwin)
    local historical = tostring(hwin)
    if mindist > cfg.mindist and not historical:match("^#") then
        if alert.send(channel, "shape",
                      string.format(shape_template,
                                    os.date("%Y%m%d %H%M%S", args.day.s / 1e9),
                                    os.date("%Y%m%d %H%M%S", args.day.e / 1e9),
                                    tostring(cwin),
                                    historical,
                                    mindist,
                                    cfg.mindist,
                                    alert.get_dashboard_uri("volume"))) then
        volume:annotate(ns, args.col, "alert", string.format("shape %.4g", mindist))
        return true
        end
    end
    return false
end


local function alert_check_latency(ns, channel, cfg, args)
    latency_cnt = latency_cnt + 1
    if alert.throttled(channel) then return false end

    local range = latency:get_range(args.col)
    local total = stats.sum(range)
    if total < 1000 then return false end

    local cnt = stats.sum(range, 1, cfg.hours)
    local percent = 100 - (cnt / total * 100)
    if percent > cfg.percent then
        if alert.send(channel, "latency",
                      string.format("%g%% of submissions received after %d hours expected up to %g%%\n\ngraph: %s\n",
                                    percent, cfg.hours, cfg.percent, alert.get_dashboard_uri("latency"))) then
            latency:annotate(ns, args.col, "alert", string.format("%.4g%% after %d hours", percent, cfg.hours))
            return true
        end
    end
    return false
end


local function setup()
    for channel, ccfg in pairs(thresholds) do
        assert(channels[channel], string.format("invalid channel %s", channel))
        for at, cfg in pairs(ccfg) do
            if at == "volume" then
                assert(type(cfg.inactivity_timeout) == "number" and cfg.inactivity_timeout > 0 and cfg.inactivity_timeout <= 60,
                       string.format("channel: %s alert: %s must contain a numeric inactivity_timeout (1-60)", channel, at))
                if cfg.percent_delta then
                    assert(type(cfg.percent_delta) == "number" and cfg.percent_delta > 0 and cfg.percent_delta <= 100,
                           string.format("channel: %s alert: %s must contain a numeric percent_delta (1-100)", channel, at))
                end
                cfg._fp = alert_check_volume
            elseif at == "size" then
                assert(type(cfg.average) == "number",
                       string.format("channel: %s alert: %s must contain a numeric average", channel, at))
                assert(type(cfg.percent_delta) == "number" and cfg.percent_delta > 0 and cfg.percent_delta <= 100,
                       string.format("channel: %s alert: %s must contain a numeric percent_delta (1-100)", channel, at))
                cfg._fp = alert_check_size
            elseif at == "ingestion_error" then
                assert(type(cfg.percent) == "number" and cfg.percent > 0 and cfg.percent <= 100,
                       string.format("channel: %s alert: %s must contain a numeric percent (1-100)", channel, at))
                diagnostics[channel] = {}
                cfg._fp = alert_check_ingestion_error
            elseif at == "duplicate" then
                assert(type(cfg.percent) == "number" and cfg.percent > 0 and cfg.percent <= 100,
                       string.format("channel: %s alert: %s must contain a numeric percent (1-100)", channel, at))
                cfg._fp = alert_check_duplicate
            elseif at == "shape" then
                assert(type(cfg.mindist) == "number", string.format("channel: %s alert: %s must contain a numeric mindist", channel, at))
                cfg._fp = alert_check_shape
            elseif at == "latency" then
                assert(type(cfg.hours) == "number" and cfg.hours > 0 and cfg.hours <= 192,
                       string.format("channel: %s alert: %s must contain a numeric hours (1-192)", channel, at))
                assert(type(cfg.percent) == "number" and cfg.percent > 0 and cfg.percent <= 100,
                       string.format("channel: %s alert: %s must contain a numeric percent (1-100)", channel, at))
                cfg._fp = alert_check_latency
            else
                error("invalid alert type " .. at)
            end
        end
    end
end
setup()
