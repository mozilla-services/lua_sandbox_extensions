# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(gzfile VERSION 0.0.3 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "gzip File Access Functions")
set(CPACK_DEBIAN_PACKAGE_DEPENDS " zlib1g (>= 1:1.1.4)")
find_package(ZLIB)
set(MODULE_SRCS gzfile.c gzfile.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
include(sandbox_module)

target_link_libraries(gzfile ${ZLIB_LIBRARIES})
if(MSVC)
  target_link_libraries(gzfile ${LUA_LIBRARIES})
endif()
