# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(moz-security VERSION 0.0.5 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Mozilla Infrastructure Security Analysis")
include(sandbox_module)

add_test(NAME ${MODULE_NAME}_hindsight
  COMMAND run.sh
  CONFIGURATIONS hindsight
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/hindsight)
