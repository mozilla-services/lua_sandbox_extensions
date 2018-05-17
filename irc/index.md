# IRC Module

## Overview

The IRC module can be used from Lua to create a persistent background connection to
an IRC server. The implementation lacks most features, and is intended primarily
to provide an simple output mechanism for writing real-time operational data from
a Lua sandbox to an IRC channel.

This package also contains an integration with the Heka alert module that can be used
by plugins to dispatch alerts to an IRC channel.

## Module

### Example Usage

```lua
i = require "irc"
conn = i.new("mynick", "server.hostname", 6697, "#mychannel")
conn:write_chan("Space... the final frontier.")
```

### Functions

#### new

Create a new persistent background IRC connection. Note that only connections to
SSL/TLS ports are supported.

```lua
conn = i.new("mynick", "server.hostname", 6697, "#mychannel")
```

*Arguments*
* nick (string)
* server (string)
* port (integer)
* channel (string)
* channel key (string, optional)

*Return*
* ircconn (userdata) or an error is thrown

### ircconn Methods

#### status

Return a table containing information about the connection.

```lua
print(conn:status().server)
```

*Arguments*
* None

*Returns*
* status (table) A table containing information about the connection

#### write_chan

Write a message to the channel the connection is configured to use. This places the
text into a queue in the module, and the module will only output one message to the
channel per second.

```lua
conn:write_chan("Some text")
```

*Arguments*
* msg (string)

*Returns*
* None

#### write_raw

Send a raw command to the IRC server.

```lua
conn:write_raw("PRIVMSG wesley :Take us out of orbit Mr Crusher.")
```

*Arguments*
* raw command (string)

*Returns*
* None
