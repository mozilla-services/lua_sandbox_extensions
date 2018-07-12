# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-security VERSION 0.0.19 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Infrastructure Security Analysis")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-streaming-algorithms (>= 0.0.2)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
set(COPY_TEST_MAXMINDDB TRUE)
include(sandbox_module)

set(integration_tests
  analysis_hh
  analysis_sshd_login_monitor
  analysis_auth_ip_geo
  analysis_auth_lastx
  analysis_iprepd_alerts
  analysis_error_rate
  analysis_webinj
  analysis_pathsetfreq
  analysis_duo
  analysis_cloudtrail
)

foreach(test IN LISTS integration_tests)
  add_test(NAME ${PROJECT_NAME}_${test}
    COMMAND ../run.sh
    CONFIGURATIONS integration
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/${test})
endforeach()
