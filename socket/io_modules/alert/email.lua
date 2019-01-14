-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Email Alert Output Module

## Sample Configuration
```lua
alert = {
    modules = {
        email = {
            from        = "hindsight@example.com",
            server      = "localhost",  -- optional, default shown
            port        = 25,           -- optional, default shown, defaults to 465 for SSL/TLS
            timeout     = 15,           -- optional, default shown
            user        = "smtp_user",  -- optional
            _password   = "password",   -- optional unsafe LOGIN/PLAIN auth only use with SSL/TLS
            ssl_params  = {  -- optional
                mode        = "client",
                protocol    = "tlsv1",
            }
        },
    }
}

```

## Functions

### send

Function that actually composes and delivers the email alert

*Arguments*
- msg (table) - Heka alert message
- cfg (array) - module configuration variables extracted from the message

*Return*
- error (string/nil)
--]]

-- Imports
local string = require "string"
local module_name = string.match(..., "%.([^.]+)$")

local cfg = read_config("alert")
assert(type(cfg) == "table", "alert configuration must be a table")
assert(type(cfg.modules) == "table", "alert.modules configuration must be a table")

cfg = cfg.modules[module_name]
assert(type(cfg) == "table", "alert.modules." .. module_name .. " configuration must be a table")

assert(type(cfg.from) == "string", "alert.email.from must be a string")
cfg.from = string.format("<%s>", cfg.from)

assert(not cfg.server or type(cfg.server) == "string", "alert.email.server must be a string")
assert(not cfg.port or type(cfg.port) == "number", "alert.email.port must be a number")
if not cfg.port and cfg.ssl_params then cfg.port = 465 end

if not cfg.timeout then cfg.timeout = 15 end
assert(type(cfg.timeout) == "number", "alert.email.timeout must be a number")

local smtp   = require "socket.smtp"
smtp.TIMEOUT = cfg.timeout

local require       = require
local setmetatable  = setmetatable
local assert        = assert
local type          = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function ssl()
end

local email = {
    from   = cfg.from,
    server = cfg.server,
    port   = cfg.port,
}

if cfg.ssl_params then
    local socket  = require "socket"
    local ssl     = require "ssl"
    local ssl_ctx = assert(ssl.newcontext(cfg.ssl_params))

    email.create = function ()
        local sock = socket.tcp()
        return setmetatable({
            connect = function(_, host, port)
                sock:settimeout(cfg.timeout)
                local r, err = sock:connect(host, port)
                if not r then return r, err end

                 sock, err = ssl.wrap(sock, ssl_ctx)
                 if sock then
                     sock:dohandshake()
                 end
                return sock, err
            end
        }, {
            __index = function(t, n)
                return function(_, ...)
                    return sock[n](sock, ...)
                end
            end
        })
     end
end

local content = {
    headers = {
        from = cfg.from,
        to = 'AlertRecipients <noreply@example.com>',
        subject = ""
    },
    body = ""
}

function send(msg, mcfg)
    content.headers.subject = msg.Fields[2].value[1]
    content.body = msg.Payload
    if type(mcfg.footer) == "string" then
        content.body = content.body .. mcfg.footer
    end

    email.rcpt      = mcfg.recipients
    email.user      = cfg.user
    email.password  = cfg._password
    email.source    = smtp.message(content)

    local ok, err = smtp.send(email)
    return err
end

return M
