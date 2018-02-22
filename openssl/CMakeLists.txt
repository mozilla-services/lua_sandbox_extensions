# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(openssl LANGUAGES NONE)

externalproject_add(
    ep_openssl
    GIT_REPOSITORY https://github.com/zhaozg/lua-openssl.git
    GIT_TAG 2e8930c5e13b52705ba9c390110e84b1f4748ba9
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt &&
        ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/config.h.in <SOURCE_DIR>/src/config.h.in
    PATCH_COMMAND patch -p1 < ${CMAKE_CURRENT_LIST_DIR}/patch.diff
)
externalproject_add_step(ep_openssl copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
