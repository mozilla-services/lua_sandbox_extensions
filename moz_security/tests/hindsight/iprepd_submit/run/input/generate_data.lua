-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local r = require "heka.iprepd"

function process_message(cp)
    local iptab = {}
    for i=1,255,1 do
        iptab[#iptab+1] = {ip = string.format("192.168.0.%d", i), violation = "fxa:heavy_hitter_ip"}
        iptab[#iptab+1] = {ip = string.format("192.168.1.%d", i), violation = "fxa:heavy_hitter_ip"}
        iptab[#iptab+1] = {ip = string.format("192.168.2.%d", i), violation = "fxa:heavy_hitter_ip"}
        iptab[#iptab+1] = {ip = string.format("192.168.3.%d", i), violation = "fxa:heavy_hitter_ip"}
    end
    r.send(iptab)
    return 0
end
