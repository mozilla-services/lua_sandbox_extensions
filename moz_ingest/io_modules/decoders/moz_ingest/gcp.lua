-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla GCP Decoder Module
GCP Pub/Sub gzip decoder

## Decoder Configuration Table
- none

## Functions

### decode

Decode and inject the generic ingestion pub/sub message

*Arguments*
- data (string) - gzipped payload
- msg (string)  - pub/sub attributes

*Return*
- none, injects an error message on decode failure

--]]

-- Imports
local inflate   = require "zlib".inflate
local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, msg)
    msg.Payload = inflate(31)(data)
    inject_message(msg)
end

return M
