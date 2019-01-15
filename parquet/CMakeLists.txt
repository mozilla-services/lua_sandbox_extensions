# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5)
project(parquet VERSION 0.0.12 LANGUAGES C CXX)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Parquet Lua Module")

find_package(parquet-cpp 1.3.1 REQUIRED CONFIG)

set(MODULE_SRCS parquet.cpp parquet.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
set(CPACK_DEBIAN_PACKAGE_DEPENDS "parquet-cpp (>= 1.3.1), ${PACKAGE_PREFIX}-lpeg (>= 1.0)")
include(sandbox_module)
target_link_libraries(parquet ${PARQUET-CPP_LIBRARIES})
