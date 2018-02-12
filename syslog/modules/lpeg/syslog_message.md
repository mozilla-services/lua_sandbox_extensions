# [DEPRECATED] Syslog Message Module


## Functions

### get_prog_grammar

Retrieves the parser for a particular program.

*Arguments*
- prog (string) - program name e.g. "CRON", "dhclient", "dhcpd"...

*Return*
- grammar (LPEG user data object) or nil if the `programname` isn't found

### get_wildcard_grammar

*Arguments*
- prog (string) - program name, currently only accepts "PAM"

*Return*
- grammar (LPEG user data object) or nil if the `programname` isn't found


source code: [syslog_message.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/syslog/modules/lpeg/syslog_message.lua)
