# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(elasticsearch VERSION 1.0.4 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Elasticsearch encoders and outputs")
set(MODULE_DEPENDENCIES heka_copy_tests rjson ep_cjson ep_socket) # fail the build if all the required modules were not specified
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-heka (>= 1.0), ${PACKAGE_PREFIX}-rjson (>= 1.0), ${PACKAGE_PREFIX}-cjson (>= 2.1), ${PACKAGE_PREFIX}-socket (>= 3.0)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)
