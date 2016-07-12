-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "bloom_filter"

bf = bloom_filter.new(20, 0.01)

local ok, err = pcall(bf.fromstring, bf, {})
assert(not ok) --incorrect argument type

local ok, err = pcall(bf.fromstring, bf, "                       ")
assert(not ok) --incorrect argument length

function process(ts)
    if not bf:query(ts) then
        if not bf:add(ts) then
            error("key existed")
        end
    end

    return 0
end

function report(tc)
    if tc == 99 then
        bf:clear()
    else
        write_output(bf:count())
    end
end

