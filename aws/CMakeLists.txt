# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5)
project(aws VERSION 0.0.5 LANGUAGES C CXX)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "AWS Lua Modules")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox-lpeg (>= 1.0.9), luasandbox-heka (>= 1.1.22), luasandbox-xxhash (>= 0.0.1)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})

set(AWS_VERSION 1.1.46)
find_package(aws-cpp-sdk-core ${AWS_VERSION} REQUIRED CONFIG)
find_package(aws-cpp-sdk-kinesis ${AWS_VERSION} REQUIRED CONFIG)
find_package(aws-cpp-sdk-monitoring ${AWS_VERSION} REQUIRED CONFIG)
find_package(aws-cpp-sdk-sts ${AWS_VERSION} REQUIRED CONFIG)
find_package(aws-cpp-sdk-cognito-identity ${AWS_VERSION} REQUIRED CONFIG)
find_package(aws-cpp-sdk-identity-management ${AWS_VERSION} REQUIRED CONFIG)

set(MODULE_SRCS kinesis.cpp aws.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
set(TEST_CONFIGURATION "aws")
include(sandbox_module)
target_link_libraries(aws
  aws-cpp-sdk-kinesis
  aws-cpp-sdk-monitoring
  aws-cpp-sdk-sts
  aws-cpp-sdk-cognito-identity
  aws-cpp-sdk-identity-management)
