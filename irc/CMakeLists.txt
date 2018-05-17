# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(irc VERSION 0.0.1 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "IRC module")
include(sandbox_module)

set(IRC_MODULE_SRCS irc.c)

set(CMAKE_C_FLAGS           "-std=gnu99 -pedantic -Werror -Wall -Wextra -fPIC")
set(CMAKE_C_FLAGS_RELEASE   "-O2")

find_package(OpenSSL REQUIRED)
add_library(irc SHARED ${IRC_MODULE_SRCS})
target_link_libraries(irc ${OPENSSL_LIBRARIES})

install(TARGETS irc DESTINATION ${INSTALL_IOMODULE_PATH})
