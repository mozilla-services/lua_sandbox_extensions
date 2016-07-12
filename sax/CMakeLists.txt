# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(sax LANGUAGES NONE)

externalproject_add(
    ep_sax
    GIT_REPOSITORY https://github.com/trink/symtseries.git
    GIT_TAG bd2426c93d0d55977ca7b21354105463b0470a49
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_sax copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
