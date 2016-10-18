# Lua Sandbox Extensions

## Overview

Package management for [Lua Sandbox](http://mozilla-services.github.io/lua_sandbox/)
modules and sandboxes. The goal is to simplify the lua_sandbox core by
decoupling the module and businesss logic maintenance and deployment.

[Full Documentation](http://mozilla-services.github.io/lua_sandbox_extensions)

## Installation

### Prerequisites
* C compiler (GCC 4.7+, Visual Studio 2013)
* CMake (3.5+) - http://cmake.org/cmake/resources/software.html
* Git http://git-scm.com/download
* luasandbox (1.2+) https://github.com/mozilla-services/lua_sandbox
* Module specific (i.e. if buiding the ssl module openssl will be required)

#### Optional (used for documentation)
* pandoc (1.17) - http://pandoc.org/
* lua (5.1) - https://www.lua.org/download.html

### CMake Build Instructions

    git clone https://github.com/mozilla-services/lua_sandbox_extensions.git
    cd lua_sandbox_extensions
    mkdir release
    cd release

    # UNIX
    cmake -DCMAKE_BUILD_TYPE=release -DENABLE_ALL_EXT=true -DCPACK_GENERATOR=TGZ ..
    # or cherry pick using -DEXT_xxx=on i.e. -DEXT_lpeg=on (specifying no
    # extension will provide a list of all available extensions)
    make
    ctest
    make packages

    # Windows Visual Studio 2013
    cmake -DCMAKE_BUILD_TYPE=release -G "NMake Makefiles" -DEXT_lpeg=on ..
    nmake
    ctest
    nmake packages

## Decoder API Convention

Each decoder module should implement a decode function according to the
specification below. Also, if the decoder requires configuration options it
should look for a table, in the cfg, with a variable name matching the module
name (periods replaced by underscores "decoders.foo" -> "decoders_foo"). This
naming convention only allows for a single instance of each decoder per sandbox
i.e., if you need to parse more than one type of Nginx access log format you
should use multiple input sandboxes (one for each).

### decode

The decode function should parse, decode, and/or transform the original data and
inject one or more Heka messages into the system.

*Arguments*
- data (string) - Raw data from the input sandbox that needs
  parsing/decoding/transforming
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- (nil, string)
    - nil - if the decode was successful
    - string - error message if the decode failed (e.g. no match)
    - error - throws an error on invalid data or an inject message failure

## Encoder API Convention

Each encoder module should implement an encode function according to the
specification below. Also, if the encoder requires configuration options it
should look for a table, in the cfg, with a variable name matching the module
name (periods replaced by underscores "encoders.foo" -> "encoders_foo").

### encode

The encode function should concatenate, encode, and/or transform the Heka
message into a byte array.

*Arguments*
- none

*Return*
- data (string, userdata, nil)
    - string - raw data ready to be output
    - userdata - a userdata object that supports the lua_sandbox zero copy API
    - nil - the output sandbox should skip the message and return -2
    - error - throws an error on an invalid transformation or incompatible
      userdata
