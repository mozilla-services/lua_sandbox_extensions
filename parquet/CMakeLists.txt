# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5)
project(parquet VERSION 0.0.1 LANGUAGES C CXX)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Parquet Lua Module")

find_package(parquet-cpp 0.0.1 REQUIRED CONFIG)

set(MODULE_SRCS parquet.cpp parquet.def)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.0), parquet-cpp (>= 0.0.1), luasandbox-lpeg (>= 1.0), libc6 (>= 2.14), libgcc1 (>= 1:4.1.1), libstdc++6 (>= 4.1.1)")
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})

include(sandbox_module)
add_dependencies(parquet ep_lpeg)

target_link_libraries(parquet ${PARQUET-CPP_LIBRARIES})
