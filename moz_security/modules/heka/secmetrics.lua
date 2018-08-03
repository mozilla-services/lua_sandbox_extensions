-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka secmetrics Module

This module can be included in analysis modules to produce metrics for consumption by
the metrics output module. This is intended to provide a uniform and consistent interface
for metrics generation.

The intent of this module is to provide updates on metrics to the metrics output sandbox. Analysis
plugins can choose to create and submit metrics in process_event, or if desired send accumulated
metrics in a timer event. Either way, each time the send function is called to generate a metrics
event the data structure is reset. It is up to the metrics output plugin to do longer term aggregation
and collection.

Plugins that import this module must ensure a proper configuration is included that specifies
an identifier. This identifier is used to group the metrics the plugin submits. All metrics
submitted to the metrics output module that have the same identifier will be aggregated together
when the metrics output module timer event fires.

```lua
heka_secmetrics = {
    identifier = "united_federation_of_planets"
}
```

## Functions

### new

Generate a new metrics data structure. This data structure stores metrics locally, prior to submission
to the metrics output module. The table returned by this function is not serializable, so any metrics
information stored here prior to submission will be lost when the process exits.

```lua
secm = require "heka.secmetrics".new()
```

*Arguments*
- None

*Return*
- secm (table) - metrics data structure

### secm:inc_accumulator

Increment an accumulator value in the data structure. When the metrics output sandbox gets this it will
increment it's stored value for the metric name specified in the submission.

*Arguments*
- metric (string) - name of metric to increment
- cnt (integer, nil) - amount to increment by (1 if unspecified)

*Return*
- None

### secm:add_uniqitem

Add a new item to the unique item metrics tracker. When the output sandbox summarizes unique items, it will
convert the number of distinct items for a given metric into a counter.

*Arguments*
- metric (string) - name of metric to add item to
- item (string) - item being added

*Return*
- None

### secm:send

Inject a secmetrics message based on the currently collected metrics stored in the secm data
structure. After the metrics message is generated, the data structure and all counters are reset.

*Arguments*
- None

*Return*
- None
--]]

local module_name   = ...
local module_cfg    = require "string".gsub(module_name, "%.", "_")
local cfg           = read_config(module_cfg) or error(module_cfg .. " configuration not found")

assert(cfg.identifier, "identifier configuration must be set")

local setmetatable      = setmetatable
local inject_message    = inject_message
local jenc              = require "cjson".encode

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local secm = {}
secm.__index = secm

local msg = {
    Type    = "secmetrics",
    Payload = nil
}

function secm:inc_accumulator(metric, cnt)
    cnt = cnt or 1
    self.havedata = true
    if not self.buf.accumulators[metric] then
        self.buf.accumulators[metric] = cnt
        return
    end
    self.buf.accumulators[metric] = self.buf.accumulators[metric] + cnt
end

function secm:add_uniqitem(metric, item)
    self.havedata = true
    if not self.buf.uniqitems[metric] then
        self.buf.uniqitems[metric] = {}
    end
    self.buf.uniqitems[metric][item] = true
end

local function reset(s)
    s.buf = {
        identifier      = cfg.identifier,
        accumulators    = {},
        uniqitems       = {},
    }
    s.havedata = false
end

function secm:send()
    if not self.havedata then return end
    msg.Payload = jenc(self.buf)
    inject_message(msg)
    reset(self)
end

function new()
    self = setmetatable({}, secm)
    reset(self)
    return self
end

return M
