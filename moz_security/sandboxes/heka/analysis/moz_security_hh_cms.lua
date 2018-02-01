-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security Heavy Hitters, CMS + moving average

For events matching the message_matcher, this analysis plugin attempts to calculate typical
request rates while identifying and flagging anomolous request patterns.

Request counts within a given window are stored in a Count-Min sketch data structure; based on
a sample encountered during the window this data structure is used to consult request rates for
given identifiers, where an identifier exceeds a threshold it is added to an analysis list for
submission by the plugin.

## Sample Configuration
```lua
filename = "moz_security_hh_cms.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60
preserve_data = false -- This module cannot keep state at this time

id_field = "Fields[remote_addr]" -- field to use as the identifier
-- id_field_capture = ",? *([^,]+)$",  -- optional e.g. extract the last entry in a comma delimited list

sample_min_id = 5000 -- Minimum distinct identifers before a sample will be calculated
sample_max_id = 10000 -- Maximum identifiers to use for sample calculation within a window
sample_min_ev = 50000 -- Minimum number of events sampler must consume before calculation
sample_window = 60 -- Sample window size
sample_ticks = 2500 -- Recalculate sample every sample_ticks events
threshold_cap = 10 -- Threshold will be calculated average + (calculated average * cap)
-- cms_epsilon = 1 / 10000 -- optional CMS value for epsilon
-- cms_delta = 0.0001 -- optional CMS value for delta
```
--]]

require "string"
require "table"

local ostime    = require "os".time

local sample_min_id = read_config("sample_min_id") or error("sample_min_id must be configured")
local sample_max_id = read_config("sample_max_id") or error("sample_max_id must be configured")
local sample_min_ev = read_config("sample_min_ev") or error("sample_min_ev must be configured")
local sample_window = read_config("sample_window") or error("sample_window must be configured")
local sample_ticks  = read_config("sample_ticks") or error ("sample_ticks must be configured")
local threshold_cap = read_config("threshold_cap") or error("threshold_cap must be configured")
local id_field      = read_config("id_field") or error("id_field must be configured")
local id_fieldc     = read_config("id_field_capture")
local cms_epsilon   = read_config("cms_epsilon") or 1 / 10000
local cms_delta     = read_config("cms_delta") or 0.0001

local cms = require "streaming_algorithms.cm_sketch".new(cms_epsilon, cms_delta)

local alist = {}

function alist:reset()
    self.l = {}
end

function alist:add(i, c)
    if not i or not c then
        error("analysis list received nil argument")
    end
    self.l[i] = c
end

function alist:flush(t)
    for k,v in pairs(self.l) do
        if v < t then self.l[k] = nil end
    end
end

local sampler = {}

function sampler:reset()
    self.s = {}
    self.n = 0
    self.start_time = ostime()
    self.threshold = 0
    self.validtick = 0
    self.evcount = 0
end

function sampler:calc()
    if self.n < sample_min_id or self.evcount < sample_min_ev then
        return
    end
    if self.validtick < sample_ticks then
        return
    end
    self.validtick = 0
    local cnt = 0
    local t = 0
    for k,v in pairs(self.s) do
        t = t + cms:point_query(k)
        cnt = cnt + 1
    end
    self.threshold = t / cnt
    self.threshold = self.threshold + (self.threshold * threshold_cap)
    -- Remove any elements in the analysis list that no longer conform
    -- to the set threshold
    alist:flush(self.threshold)
end

function sampler:add(x)
    if self.start_time + sample_window < ostime() then
        self:reset()
        alist:reset()
        cms:clear()
    end
    self.evcount = self.evcount + 1
    self.validtick = self.validtick + 1
    if self.n >= sample_max_id then
        return
    end
    -- If x is already present in the sample, don't add it again
    if self.s[x] then return end
    self.s[x] = 1
    self.n = self.n + 1
end

sampler:reset()
alist:reset()

function process_message()
    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end

    sampler:add(id)
    sampler:calc()
    local q = cms:update(id)
    if sampler.threshold ~= 0 and q > sampler.threshold then
        alist:add(id, q)
    end
    return 0
end

function timer_event(ns)
    -- For now, just generate a tsv here but this could be modified to submit violations
    -- with a configured confidence to Tigerblood
    add_to_payload("sampler_threshold", "\t", sampler.threshold, "\n")
    add_to_payload("sampler_size", "\t", sampler.n, "\n")
    add_to_payload("sampler_evcount", "\t", sampler.evcount, "\n")
    for k,v in pairs(alist.l) do
        add_to_payload(k, "\t", v, "\n")
    end
    inject_payload("tsv", "statistics")
end
