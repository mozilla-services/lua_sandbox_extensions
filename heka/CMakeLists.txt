# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(heka VERSION 1.1.4 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Utility modules for Heka sandboxes")
set(MODULE_DEPENDENCIES ep_cjson) # postgres is conditionaly so don't make it a dependency
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.2), ${PACKAGE_PREFIX}-cjson (>= 2.1)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})
include(sandbox_module)
