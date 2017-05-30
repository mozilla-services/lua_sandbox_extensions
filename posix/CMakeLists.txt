# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(posix LANGUAGES NONE)

externalproject_add(
    ep_posix
    # git is not usable, because of https://github.com/luaposix/luaposix/issues/250
    #GIT_REPOSITORY https://github.com/luaposix/luaposix.git
    #GIT_TAG 32694c0b6f8a90a4575f07b2731c602f021a91f2
    URL https://github.com/luaposix/luaposix/archive/release-v33.4.0.tar.gz
    URL_MD5 b36ff049095f28752caeb0b46144516c
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_posix copy_cpack
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
