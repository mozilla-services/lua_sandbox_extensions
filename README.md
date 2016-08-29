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
* luasandbox (1.1+) https://github.com/mozilla-services/lua_sandbox
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
