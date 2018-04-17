# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5)
project(aws VERSION 0.0.3 LANGUAGES C CXX)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "AWS Lua Modules")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox-lpeg (>= 1.0.9)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})

find_package(aws-cpp-sdk-core 1.1.46 REQUIRED CONFIG)
find_package(aws-cpp-sdk-kinesis 1.1.46 REQUIRED CONFIG)
find_package(aws-cpp-sdk-monitoring 1.1.46 REQUIRED CONFIG)

set(MODULE_SRCS kinesis.cpp aws.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
set(TEST_CONFIGURATION "aws")
include(sandbox_module)
target_link_libraries(aws aws-cpp-sdk-kinesis aws-cpp-sdk-monitoring)
