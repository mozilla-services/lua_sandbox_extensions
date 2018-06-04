#  Mozilla Security Tigerblood Reputation Alerts

Monitors Tigerblood log events and generates notices when the reputation of a
given IP falls below certain thresholds (<=75, <=50, <=25).

The alerting key is generated based on the passed threshold and the IP address,
to suppress further notifications about changes within a given window.

## Sample Configuration
```lua
filename = "moz_security_tb_alerts.lua"
message_matcher = "Type =~ 'logging.tigerblood.app.docker'%"
ticker_interval = 0
process_message_inject_limit = 1

prefix = "hhfxa" -- define a prefix to include with the alert messages

-- module makes use of alert output and needs a valid alert configuration
alert = {
    modules = { }
}
```


source code: [moz_security_tb_alerts.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/moz_security/sandboxes/heka/analysis/moz_security_tb_alerts.lua)
