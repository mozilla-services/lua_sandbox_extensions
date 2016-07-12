-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "bloom_filter"

bf = bloom_filter.new(2e6, 0.01)

function process(ts)
    bf:add(ts)
    return 0
end

function report(tc)
    write_output(bf:count())
end

