# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(irc VERSION 0.0.1 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "IRC module")
find_package(OpenSSL REQUIRED)
set(MODULE_SRCS irc.c)
include(sandbox_module)
string(REPLACE "-std=c99" "-std=gnu99" CMAKE_C_FLAGS ${CMAKE_C_FLAGS})
target_link_libraries(irc ${OPENSSL_LIBRARIES})
