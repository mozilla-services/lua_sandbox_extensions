# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-telemetry VERSION 1.2.5 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Firefox Telemetry Data Processing")
set(MODULE_DEPENDENCIES ep_cjson rjson)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.2), ${PACKAGE_PREFIX}-lsb (>= 1.1.0), ${PACKAGE_PREFIX}-circular-buffer (>= 1.0.2), ${PACKAGE_PREFIX}-heka (>= 1.1.7), ${PACKAGE_PREFIX}-elasticsearch (>= 1.0.3), ${PACKAGE_PREFIX}-rjson (>= 1.0.2)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)
