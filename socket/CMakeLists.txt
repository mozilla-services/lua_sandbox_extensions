# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(socket LANGUAGES NONE)

externalproject_add(
    ep_socket
    GIT_REPOSITORY https://github.com/diegonehab/luasocket
    GIT_TAG 30a64c585a444d3007976a4b4a1b8014d7797e04
    CMAKE_ARGS ${EP_CMAKE_ARGS} -DPARENT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_socket copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
