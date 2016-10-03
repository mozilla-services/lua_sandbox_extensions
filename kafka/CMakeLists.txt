# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(kafka VERSION 1.0.4 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lua Kafka producer/consumer module")

# todo add a more robust kafka check
find_library(LIBRTKAFKA_LIBRARY rdkafka REQUIRED)

set(MODULE_SRCS kafka.c kafka.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
set(INTEGRATION_TEST TRUE)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox (>= 1.2), librdkafka-dev (>= 0.9)")
include(sandbox_module)
target_link_libraries(kafka ${LIBRTKAFKA_LIBRARY})
