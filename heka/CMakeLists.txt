# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(heka VERSION 1.0.0 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Utility modules for Heka sandboxes")
set(MODULE_DEPENDENCIES ep_cjson)
set(PACKAGE_DEPENDENCIES_EXTRA "${PACKAGE_PREFIX}-cjson")
include(sandbox_module)
