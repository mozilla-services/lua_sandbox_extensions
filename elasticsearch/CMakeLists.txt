# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(elasticsearch VERSION 1.0.0 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Elasticsearch encoders and outputs")
set(MODULE_DEPENDENCIES heka_copy_tests rjson ep_cjson ep_socket) # fail the build if all the required modules were not specified
set(PACKAGE_DEPENDENCIES_EXTRA "${PACKAGE_PREFIX}-heka,${PACKAGE_PREFIX}-rjson,${PACKAGE_PREFIX}-cjson,${PACKAGE_PREFIX}-socket")
include(sandbox_module)
