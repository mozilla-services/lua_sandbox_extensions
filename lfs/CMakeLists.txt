# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(lfs LANGUAGES NONE)

externalproject_add(
    ep_lfs
    GIT_REPOSITORY https://github.com/keplerproject/luafilesystem.git
    GIT_TAG 50919ed69ff64df51d8d586d00834fde3e901785
    CMAKE_ARGS ${EP_CMAKE_ARGS} -DPARENT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_lfs copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
