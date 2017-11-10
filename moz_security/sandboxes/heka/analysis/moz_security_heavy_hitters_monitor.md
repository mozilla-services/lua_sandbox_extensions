#  Mozilla Security Heavy Hitters Monitor

See: https://cacm.acm.org/magazines/2009/10/42481-finding-the-frequent-items-in-streams-of-data/abstract

## Sample Configuration
```lua
filename = "moz_security_heavy_hitters.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60

id_field = "Fields[remote_addr]"
-- hh_items = 1000 -- optional, defaults to 1000 (maximum number of heavy hitter IDs to track)

cf_items = 100e6
-- cf_interval_size = 1, -- optional, default 1 (256 minutes)

-- update if altering the cf_* configuration of an existing plugin
preservation_version = 0
preserve_data = true

alert = {
    prefix = true,
    throttle = 1,
    modules = {
        email = {recipients = {"pagerduty@mozilla.com"}}
    }
}
```


source code: [moz_security_heavy_hitters_monitor.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/moz_security/sandboxes/heka/analysis/moz_security_heavy_hitters_monitor.lua)
