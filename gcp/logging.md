# GCP Logging (Stackdriver) Module (POC)

## Overview
Lua wrapper for the GCP gRPC Logging APIs. This is a proof of concept, so it is
functional but not 100% complete and subject to change. Since the 'List'
interface is a query mechanism and not really suited for streaming it is
recommended that the StackDriver logs be exported to pub/sub if you are looking
for that type of functionality. Therefore a 'List' interface will not be
provided.

## Module

### Example Usage

```lua
require "gcp.logging"
```

### Functions

#### writer

Creates a log writer.

```lua
local writer = gcp.logging.writer(channel, max_async_requests, batch_size)
```

*Arguments*
* channel (string) e.g. "google.logging.v2"
* max_async_requests (integer) Defaults to 20 (0 synchronous only)
* batch_size (integer) Defaults to 1000

*Return*
* writer (userdata) or an error is thrown

### writer methods

#### send, send_sync

Sends a log entry to StackDriver.

```lua
writer.send(sequence_id, log_entry)
writer.send_sync(log_entry)
```

*Arguments*
* sequence_id Used with send() only
    * luasandbox (lightuserdata) Opaque pointer for checkpointing
    * Lua 5.1 (number) range: zero to UINTPTR_MAX
* log_entry (table) LogEntry schema (supported schema follows)
  supported schema.
```lua
    logName = string,                  -- required

    resource = {                       -- required
        type    = "gce_instance",      -- required
        labels  = {                    -- required
            instance_id = "12345678901234",
            zone        = "us-central1-a"
            }
        }

    timestamp   = number, -- nanoseconds since the Unix epoch
    severity    = number, -- syslog severity (converted to gcp severity by write)
    insertId    = string,

    httpRequest = {
        requestMethod       = string, -- "GET",
        requestUrl          = string, -- "/",
        requestSize         = number, -- 123,
        status              = number, -- 200,
        responseSize        = number, -- 2322,
        userAgent           = string, -- "Mozilla/4.0 (compatible; MSIE 6.0; Windows 98; Q312461; .NET CLR 1.0.3705)",
        remoteIp            = string, -- "192.168.1.1",
        serverIp            = string, -- "127.0.0.1",
        referer             = string, -- "",
        latency             = number, -- 123000, --- nanoseconds
        cacheLookup         = boolean, -- true,
        cacheHit            = boolean, -- true,
        cacheValidatedWithOriginServer = boolean, -- true,
        cacheFillBytes      = number, -- 344,
        protocol            = string  -- "HTTP/1.1"
        },

    labels = {
        -- string = string -- foo = "bar"
        },

    operation = {
        id          = string, -- "",
        producer    = string, -- "",
        first       = boolean, -- true,
        last        = boolean  -- false
        },

    trace           = string, -- "projects/my-projectid/traces/06796866738c859f2f19b7cfb3214824",
    span_id         = string, -- "000000000000004a",

    sourceLocation = {
        file        = string, -- "",
        line        = number, -- 0,
        ["function"]= string -- ""
        },

    textPayload = string
}
```

*Return*
* status_code (integer) or throws an error
    * sent (0)
    * failed (-1)
    * skip (-2)
    * retry (-3)
    * batched (-4)
    * async (-5)
* error (nil/string)

#### flush

Flushes the batched log entries over the network.

```lua
writer.flush()
```

*Arguments*
none

*Return*
* none or throws an error
