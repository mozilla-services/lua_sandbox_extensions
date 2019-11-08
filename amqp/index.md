# Lua AMQP Module

## Overview

**WORK IN PROGRESS** currently consumer only

A RabbitMQ AMQP producer/consumer library for Lua

## Module

### Example Usage
```lua
require "amqp"
local consumer = amqp.receive(cfg)
msg, exchange, routing_key = consumer:receive()
if msg then
--[=[
-- msg
{
    Uuid        = "<binary>",
    Timestamp   = 0, -- receive time nanoseconds
    Logger      = "input.amqp",
    Hostname    = "hindsight.example.com",
    Pid         = 1234,
    Fields = {
        timestamp           = 0, -- nanoseconds
        content_type        = "",
        content             = "", -- byte array, not stored in Payload as that technically has a UTF-8 restriction

        -- TBD these additional properties will not be extracted at this point
        content_encoding    = "",
        priority            = 0,
        message_id          = "",
        type                = "",
        user_id             = "",
        app_id              = "",
        cluster_id          = "",
        header.*            = <primitive type> -- arrays/tables not supported
    }
--]=]
end
```

### Functions

#### consumer

Creates an AMQP consumer.

```lua
local consumer = amqp.consumer(cfg)
```

*Arguments*
* cfg (table)
``` lua
host                = "amqp.example.com",
vhost               = "/", -- default
port                = 5672, -- default
user                = "guest",
_password           = "guest",
connect_timeout     = 10, -- default seconds
exchange            = "exchange/foo/bar",
binding             = "#",
queue_name          = nil, -- creates an exclusive/temporary queue
manual_ack          = false,
passive             = false,
durable             = false,
exclusive           = false,
auto_delete         = false,
prefetch_size       = 0,
prefetch_count      = 1, -- default, read one at a time
ssl = { -- optional if not provided ssl is disabled use ssl = {} to enable with defaults
    _key            = nil,  -- path to client key
    cert            = nil,  -- path to client cert
    cacert          = nil,  -- path to credential authority cert
    verifypeer      = false,
    verifyhostname  = false
}
```

*Return*
* consumer (userdata) - AMQP consumer or an error is thrown

#### version
```lua
require "amqp"
local v = amqp.version()
-- v == "0.0.1"
```

Returns a string with the running version of AMQP module.

*Arguments*
- none

*Return*
- Semantic version string


### Consumer Methods

#### receive

Receives a message from the specified AMQP exchange.  Throws on fatal error.

```lua
local msg = consumer:receive()

```

*Arguments*
* none

*Return*
* msg (table) -- currently just the body
* content_type (string)
* exchange (string)
* routing_key (string)

#### ack

Acknowledges the last message received, this function MUST be called after
the processing of each message is complete when the manual_ack configuration is
true.

```lua
local ok = consumer:ack()

```

*Arguments*
* none

*Return*
* bool

