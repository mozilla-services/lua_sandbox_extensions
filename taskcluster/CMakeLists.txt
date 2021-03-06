# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(taskcluster VERSION 0.0.25 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Taskcluster Data Processing")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-amqp (>= 0.0.1), ${PACKAGE_PREFIX}-gcp (>= 0.0.7), ${PACKAGE_PREFIX}-heka (>= 1.1.9), ${PACKAGE_PREFIX}-rjson (>= 1.1.4), ${PACKAGE_PREFIX}-cjson (>= 2.1), ${PACKAGE_PREFIX}-gzfile (>= 0.0.2), ${PACKAGE_PREFIX}-postgres (>= 2.5.1), ${PACKAGE_PREFIX}-lyaml (>= 6.2.5)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)

set(integration_tests
  taskcluster
  worker_metrics
  taskcluster_backfill
)

foreach(test IN LISTS integration_tests)
  add_test(NAME ${PROJECT_NAME}_${test}
    COMMAND ../run.sh
    CONFIGURATIONS integration
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/integration/${test})
endforeach()
