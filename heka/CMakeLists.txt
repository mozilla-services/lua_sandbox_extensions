# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(heka VERSION 1.1.17 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Utility modules for Heka sandboxes")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-cjson (>= 2.1), ${PACKAGE_PREFIX}-lpeg (>= 1.0.10)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

set(integration_tests
  decoder_table_to_message
  input_file
)

foreach(test IN LISTS integration_tests)
  add_test(NAME ${PROJECT_NAME}_${test}
    COMMAND ../run.sh
    CONFIGURATIONS integration
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/${test})
endforeach()
