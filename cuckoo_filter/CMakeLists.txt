# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(cuckoo-filter VERSION 1.1.0 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lua cuckoo filter module (membership test with deletion support)")
set(MODULE_SRCS cuckoo_filter.c common.c ../common/xxhash.c cuckoo_filter.def)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.0)")
include(sandbox_module)

include_directories(${LUA_INCLUDE_DIR})
add_library(cuckoo_filter_expire SHARED cuckoo_filter_expire.c common.c ../common/xxhash.c cuckoo_filter_expire.def)
target_link_libraries(cuckoo_filter_expire ${LUA_LIBRARIES})
set(EMPTY_DIR ${CMAKE_BINARY_DIR}/empty)
file(MAKE_DIRECTORY ${EMPTY_DIR})
install(DIRECTORY ${EMPTY_DIR}/ DESTINATION ${INSTALL_MODULE_PATH} ${DPERMISSION})
install(TARGETS cuckoo_filter_expire DESTINATION ${INSTALL_MODULE_PATH})
