# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(geoip LANGUAGES NONE)

externalproject_add(
    ep_geoip
    GIT_REPOSITORY https://github.com/agladysh/lua-geoip.git
    GIT_TAG a07d261d8a2c7ff854fe6cd72cb8c2e16ec638ff
    CMAKE_ARGS ${EP_CMAKE_ARGS}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_geoip copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
