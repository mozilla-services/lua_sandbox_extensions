# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-ingest VERSION 0.0.10 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Nginx Ingestion Data Processing")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-rjson (>= 1.1.4), ${PACKAGE_PREFIX}-lpeg (>= 1.0.0), ${PACKAGE_PREFIX}-lfs (>= 1.6.4), ${PACKAGE_PREFIX}-zlib (>= 0.3.1)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

add_test(NAME ${PROJECT_NAME}_decoder_common
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/decoder_common)

add_test(NAME ${PROJECT_NAME}_decoder_json
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/decoder_json)

add_test(NAME ${PROJECT_NAME}_doctype_monitor
  COMMAND ../run.sh
  CONFIGURATIONS integration
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/doctype_monitor)
