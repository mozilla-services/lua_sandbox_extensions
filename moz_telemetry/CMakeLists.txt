# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz_telemetry VERSION 1.0.0 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Firefox Telemetry Data Processing")
set(MODULE_DEPENDENCIES ep_cjson rjson)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "${PACKAGE_PREFIX}-elasticsearch (>= 1.0)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)
