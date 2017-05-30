# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(syslog VERSION 1.0.7 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Syslog parsers and collectors")
set(MODULE_DEPENDENCIES ep_lpeg ep_socket)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.1), ${PACKAGE_PREFIX}-lpeg (>= 1.0.5)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)
