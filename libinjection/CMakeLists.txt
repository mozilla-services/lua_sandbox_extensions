# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(libinjection LANGUAGES C)

externalproject_add(
    ep_libinjection
    GIT_REPOSITORY https://github.com/client9/libinjection.git
    GIT_TAG e86ff4019a4343579cc307d96d79272d5efcd1be
    CMAKE_ARGS ${EP_CMAKE_ARGS} -DPARENT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/libinjection_wrap.c <SOURCE_DIR>/libinjection_wrap.c
)

externalproject_add_step(ep_libinjection copy_cpack
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
