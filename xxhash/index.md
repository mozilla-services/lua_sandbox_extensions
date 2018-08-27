# Lua xxhash Module

## Overview
Exposes the xxhash functions to Lua.

## Module

The module is globally registered and returned by the require function.

### Example Usage
```lua
require "xxhash"

local h = xxhash.h32("foobar")
-- h == 3986901679
```

### Functions

#### h32
```lua
require "xxhash"
local hash = xxhash.h32("foobar")
```

Thirty two bit hash function.

*Arguments*
- item (string/number) Item to hash
- seed (unsigned/nil) Used to alter the result predictably (default 0)

*Return*
- hash (unsigned)

#### h64
```lua
require "xxhash"
local hash = xxhash.h64("foobar")
```

Sixty four bit hash function.

*Arguments*
- item (string/number) Item to hash
- seed (unsigned long long/nil) Used to alter the result predictably (default 0)

*Return*
- hash (unsigned long long)
