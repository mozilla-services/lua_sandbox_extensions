# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(lpeg LANGUAGES C)

externalproject_add(
    ep_lpeg
    URL http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.0.0.tar.gz
    URL_MD5 0aec64ccd13996202ad0c099e2877ece
    CMAKE_ARGS ${EP_CMAKE_ARGS} -DPARENT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    UPDATE_COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt.${PROJECT_NAME} <SOURCE_DIR>/CMakeLists.txt
)
externalproject_add_step(ep_lpeg copy_cpack 
COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/${PROJECT_NAME}.cpack ${CMAKE_BINARY_DIR}
DEPENDEES install)
include(sandbox_ep_test)
