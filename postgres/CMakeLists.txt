# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(postgres LANGUAGES NONE)

externalproject_add(
    ep_postgres
    GIT_REPOSITORY https://github.com/keplerproject/luasql.git
    GIT_TAG 5496d60185db0c4578e8abe0c74343e99b799311
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
    PATCH_COMMAND patch src/ls_mysql.c < ${CMAKE_CURRENT_SOURCE_DIR}/patch.txt
)
externalproject_add_step(ep_postgres copy_cpack
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
