# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(syslog VERSION 1.0.12 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Syslog parsers and collectors")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-lpeg (>= 1.0.9), ${PACKAGE_PREFIX}-socket (>= 3.0)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

add_test(NAME ${PROJECT_NAME}_tutorial
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/tutorial)
