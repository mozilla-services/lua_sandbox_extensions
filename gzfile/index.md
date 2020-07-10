# gzip File Access Functions

## Overview
This library supports reading and writing files in gzip (.gz) format with an
interface similar to that of stdio, using the functions that start with "gz".
The gzip format is different from the zlib format. gzip is a gzip wrapper,
documented in RFC 1952, wrapped around a deflate stream

## Module

### Example Usage
```lua
require "gzfile"

local gzf = gzfile.open("foo.gz")
for line in gzf:lines() do
    -- process line
end
gzf:close()

```

### Functions

#### open
```lua
local gzf, err = gzfile.open(filename, mode, buffer_size)
```

Opens a file in the specified mode

*Arguments*
- filename (string) File to open.
- mode (string) defaults to "rb"
- buffer_size (unsigned) Internal buffer size (default 8192)

*Return*
- gzf (userdata object/nil)
- err (nil/string)

#### string
```lua
local s = gzfile.string(filename, mode, buffer_size, max_bytes)
```

Expands the entire gzip file into a string.

*Arguments*
- filename (string) File to open.
- mode (string) defaults to "rb"
- buffer_size (unsigned) Internal buffer size (default 8192)
- max_bytes (unsigned) The maximum length of the expanded string (default 1MB).

*Return*
- s (string/nil) throws on error

#### version
```lua
require "gzfile"
local v = gzfile.version()
-- v == "0.0.1"
```

Returns a string with the running version of the gzfile module.

*Arguments*
- none

*Return*
- Semantic version string

### Methods

#### lines
```lua
local iter = gzf:lines(max_bytes)
```

Creates an iterator to read the file one line at a time.

*Arguments*
- max_bytes (unsigned) The maximum number of bytes allowed in a line after
which the line is truncated (default 1MB).

*Return*
- line (string/nil) Returns nil at EOF

#### close
```lua
gzf:close()
```

Closes the open file

*Arguments*
- none

*Return*
- none
