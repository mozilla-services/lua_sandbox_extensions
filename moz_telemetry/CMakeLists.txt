# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-telemetry VERSION 1.2.17 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Firefox Telemetry Data Processing")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-moz-ingest (>= 0.0.1), ${PACKAGE_PREFIX}-lsb (>= 1.1.0), ${PACKAGE_PREFIX}-circular-buffer (>= 1.0.2), ${PACKAGE_PREFIX}-heka (>= 1.1.9), ${PACKAGE_PREFIX}-elasticsearch (>= 1.0.3), ${PACKAGE_PREFIX}-rjson (>= 1.1.0), ${PACKAGE_PREFIX}-lfs (>= 1.6.4)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

set(integration_tests
  decoder_telemetry
  doctype_monitor
  moz_telemetry_s3
  new_doctype_monitor
)

foreach(test IN LISTS integration_tests)
  add_test(NAME ${PROJECT_NAME}_${test}
    COMMAND ../run.sh
    CONFIGURATIONS integration
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/${test})
endforeach()
