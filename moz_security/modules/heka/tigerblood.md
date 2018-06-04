# Heka Tigerblood Module

Can be utilized by an analysis module to generate messages for the Tigerblood
output module. The send function expects a table containing violations to be forwarded
to the violations endpoint of the Tigerblood service (e.g., /violations/).

## Functions

### send

Send a violation message to be processed by the Tigerblood output plugin.

The violations argument should be an array containing tables with a violation
and ip value set.

```lua
{
    { ip = "192.168.1.1", violation = "fxa:request.check.block.accountStatusCheck" },
    { ip = "10.10.10.10", violation = "fxa:request.check.block.accountStatusCheck" }
}
```

*Arguments*
- violations - A table containing violation entries

*Return*
- sent (boolean) - true if sent, false if invalid argument


source code: [tigerblood.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/moz_security/modules/heka/tigerblood.lua)
