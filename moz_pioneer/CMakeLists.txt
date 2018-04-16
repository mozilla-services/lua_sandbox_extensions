# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-pioneer VERSION 0.0.4 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Firefox Pioneer Data Processing")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-moz-ingest (>= 0.0.1), ${PACKAGE_PREFIX}-moz-telemetry (>= 1.2.13), ${PACKAGE_PREFIX}-jose (>= 0.0.1), ${PACKAGE_PREFIX}-lpeg (>= 1.0.0), ${PACKAGE_PREFIX}-rjson (>= 1.1.0)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

add_test(NAME ${PROJECT_NAME}_decoder_moz_ingest_pioneer
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/decoder_moz_ingest_pioneer)
