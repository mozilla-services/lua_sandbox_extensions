# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5)
project(amqp VERSION 0.0.2 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "AMQP RabbitMQ Lua module")

find_package(PkgConfig REQUIRED)
pkg_search_module(RABBITMQ REQUIRED librabbitmq)

set(MODULE_SRCS amqp.c amqp.def)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
include(sandbox_module)
target_link_libraries(${MODULE_NAME} ${RABBITMQ_LIBRARIES})
