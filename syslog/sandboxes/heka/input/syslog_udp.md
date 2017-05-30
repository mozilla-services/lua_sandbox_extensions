# [DEPRECATED] Syslog UDP and UNIX socket Input
Use a UDP or systemd_socket input with a syslog decoder instead

## Sample Configuration #1
```lua
filename            = "syslog_udp.lua"
instruction_limit   = 0

-- address (string) - an IP address (* for all interfaces), or a path to an UNIX socket
-- Default:
-- address = "127.0.0.1"

-- port (integer) - IP port to listen on (ignored for UNIX socket)
-- Default:
-- port = 514

-- sd_fd (integer) - If set, systemd socket activation is tryed
-- Default:
-- sd_fd = nil

-- template (string) - The 'template' configuration string from rsyslog.conf
-- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
-- Defaults:
-- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- RSYSLOG_TraditionalForwardFormat
-- template = "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- for UNIX socket

-- send_decode_failures (bool) - If true, any decode failure will inject a
-- message of Type "error", with the Payload containing the error, and with the
-- "data" field containing the original, undecoded Payload.
```

## Sample Configuration #2: system syslog with systemd socket activation
```lua
filename            = "syslog_udp.lua"
instruction_limit   = 0

address             = "/dev/log"
sd_fd               = 0
```


source code: [syslog_udp.lua](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/syslog/sandboxes/heka/input/syslog_udp.lua)
