# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(jose VERSION 0.0.1 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lua JOSE module")

find_package(PkgConfig REQUIRED)
pkg_search_module(CJOSE REQUIRED cjose)

set(MODULE_SRCS jose.c jose.def)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libjansson4, libssl1.0.0 (>= 1.0.1)")
find_package(ZLIB)
if(ZLIB_FOUND)
  add_definitions(-DHAVE_ZLIB)
  set(CPACK_DEBIAN_PACKAGE_DEPENDS "${CPACK_DEBIAN_PACKAGE_DEPENDS}, zlib1g (>= 1:1.1.4)")
endif()
include(sandbox_module)

target_link_libraries(jose ${CJOSE_STATIC_LIBRARIES})
if(ZLIB_FOUND)
  target_link_libraries(jose ${ZLIB_LIBRARIES})
endif()
