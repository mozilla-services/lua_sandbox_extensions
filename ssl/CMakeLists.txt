# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(ssl LANGUAGES NONE)

externalproject_add(
    ep_ssl
    GIT_REPOSITORY https://github.com/brunoos/luasec.git
    GIT_TAG 98f8872743f3d38bd44cb9eedb2c82e38571fe04
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_ssl copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
