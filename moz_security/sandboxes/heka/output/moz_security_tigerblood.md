# Tigerblood Output Plugin

Sends tigerblood events to Mozilla Tigerblood IP reputation service using a
hawk/JSON request. This output plugin currently only supports submitting
IP violations to the /violations/ endpoint.

https://github.com/mozilla-services/tigerblood

## Sample Configuration
```lua
filename = "moz_security_tigerblood.lua"
message_matcher = "Type == 'tigerblood'"

-- Configuration for pushing violations to Tigerblood
tigerblood = {
   base_url     = "https://tigerblood.prod.mozaws.net", -- NB: no trailing slash
   id           = "fxa_heavy_hitters", -- hawk ID
   _key         = "hawksecret" -- hawk secret
}
```


source code: [moz_security_tigerblood.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/moz_security/sandboxes/heka/output/moz_security_tigerblood.lua)
