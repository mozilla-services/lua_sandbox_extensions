# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(hindsight VERSION 0.0.1 LANGUAGES NONE)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Hindsight Utility Sandboxes and Modules")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-lpeg (>= 1.0.10)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

add_test(NAME ${PROJECT_NAME}_plugin_monitor
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/plugin_monitor)
