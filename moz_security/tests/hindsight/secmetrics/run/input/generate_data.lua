-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local payloads = {
    '{"identifier":"iprepd_alerts","accumulators":{"violation_applied":1,"total_count":1},"uniqitems":{}}',
    '{"identifier":"iprepd_alerts","accumulators":{"violation_applied":1,"total_count":1},"uniqitems":{}}',
    '{"identifier":"iprepd_alerts","accumulators":{"violation_applied":1,"total_count":1},"uniqitems":{}}',
    '{"identifier":"iprepd_alerts","accumulators":{"violation_applied":1,"total_count":1},"uniqitems":{}}',
    '{"identifier":"iprepd_alerts","accumulators":{"violation_applied":1,"total_count":1},"uniqitems":{}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"riker":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"riker":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"riker":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"riker":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"riker":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"picard":true},"unique_sources":{"192.168.1.2":true}}}',
    '{"identifier":"auth_lastx_1","accumulators":{"alert_count":1,"total_count":1},' ..
        '"uniqitems":{"unique_users":{"picard":true},"unique_sources":{"192.168.1.2":true}}}'
}

local msg = {
    Type = "secmetrics",
    Fields = {}
}

function process_message(cp)
    for i,v in ipairs(payloads) do
        msg.Payload = v
        inject_message(msg)
    end
    return 0
end
