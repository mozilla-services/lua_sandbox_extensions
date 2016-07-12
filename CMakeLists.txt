# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0 FATAL_ERROR)
project(luasandbox-extensions LANGUAGES NONE)
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

include(GNUInstallDirs)
if(WIN32)
  set(CMAKE_INSTALL_LIBDIR ${CMAKE_INSTALL_BINDIR})
endif()
set(CMAKE_INSTALL_PREFIX "")
set(CMAKE_SHARED_LIBRARY_PREFIX "")
set(PACKAGE_PREFIX luasandbox)

if(LUA51) # build against installed lua 5.1
    find_package(Lua51)
    set(INSTALL_MODULE_PATH ${CMAKE_INSTALL_LIBDIR}/lua)
    set(INSTALL_IOMODULE_PATH ${CMAKE_INSTALL_LIBDIR}/lua)
    set(INSTALL_SANDBOX_PATH ${CMAKE_INSTALL_DATAROOTDIR}/lua)
    set(PACKAGE_PREFIX lua)
    if(WIN32)
        string(REPLACE "\\" "\\\\" TEST_MODULE_PATH "${CMAKE_BINARY_DIR}\\install\\${CMAKE_INSTALL_LIBDIR}\\${PACKAGE_PREFIX}\\?.lua")
        string(REGEX REPLACE "\\.lua$" ".dll" TEST_MODULE_CPATH ${TEST_MODULE_PATH})
    else()
        set(TEST_MODULE_PATH "${CMAKE_BINARY_DIR}/install/${CMAKE_INSTALL_LIBDIR}/${PACKAGE_PREFIX}/?.lua")
        string(REGEX REPLACE "\\.lua$" ".so" TEST_MODULE_CPATH ${TEST_MODULE_PATH})
    endif()
else() # lua_sandbox build
    find_package(luasandbox 0.24.0 REQUIRED CONFIG)
    set(LUA_LIBRARIES ${LUASANDBOX_LIBRARIES})
    set(LUA_INCLUDE_DIR ${LUASANDBOX_INCLUDE_DIR}/luasandbox)
    set(INSTALL_MODULE_PATH ${CMAKE_INSTALL_LIBDIR}/luasandbox/modules)
    set(INSTALL_IOMODULE_PATH ${CMAKE_INSTALL_LIBDIR}/luasandbox/io_modules)
    set(INSTALL_SANDBOX_PATH ${CMAKE_INSTALL_DATAROOTDIR}/luasandbox/sandboxes)
    add_definitions(-DLUA_SANDBOX)
    if(WIN32)
        string(REPLACE "\\" "\\\\" TEST_MODULE_PATH "${CMAKE_BINARY_DIR}\\install\\${CMAKE_INSTALL_LIBDIR}\\${PACKAGE_PREFIX}\\modules\\?.lua")
        string(REGEX REPLACE "\\.lua$" ".dll" TEST_MODULE_CPATH ${TEST_MODULE_PATH})
        string(REGEX REPLACE "\\modules\\\\?" "\\io_modules\\?" TEST_IOMODULE_PATH ${TEST_MODULE_PATH})
        string(REGEX REPLACE "\\.lua$" ".dll" TEST_IOMODULE_CPATH ${TEST_IOMODULE_PATH})
    else()
        set(TEST_MODULE_PATH "${CMAKE_BINARY_DIR}/install/${CMAKE_INSTALL_LIBDIR}/${PACKAGE_PREFIX}/modules/?.lua")
        string(REGEX REPLACE "\\.lua$" ".so" TEST_MODULE_CPATH ${TEST_MODULE_PATH})
        string(REGEX REPLACE "/modules/\\?" "/io_modules/?" TEST_IOMODULE_PATH ${TEST_MODULE_PATH})
        string(REGEX REPLACE "\\.lua$" ".so" TEST_IOMODULE_CPATH ${TEST_IOMODULE_PATH})
    endif()
    configure_file(${CMAKE_SOURCE_DIR}/cmake/test_module.in.h ${CMAKE_BINARY_DIR}/test_module.h)
endif()

include(CTest)
configure_file(${CMAKE_SOURCE_DIR}/cmake/CTestCustom.in.cmake ${CMAKE_BINARY_DIR}/CTestCustom.cmake)

include(ExternalProject)
set(EP_CMAKE_ARGS
-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
-DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/install
-DINSTALL_MODULE_PATH=${INSTALL_MODULE_PATH}
-DINSTALL_IOMODULE_PATH=${INSTALL_IOMODULE_PATH}
-DINSTALL_SANDBOX_PATH=${INSTALL_SANDBOX_PATH}
-DLUA51=${LUA51}
--no-warn-unused-cli)

set(extensions 
bloom_filter
circular_buffer
cjson
cuckoo_filter
elasticsearch
geoip
heka
hyperloglog
kafka
lpeg
lsb
openssl
postgres
rjson
sax
snappy
socket
ssl
struct
syslog
)

foreach(ext IN LISTS extensions)
  if(ENABLE_ALL_EXT)
    option(EXT_${ext} "include extension ${ext}" ON)
  else()
    option(EXT_${ext} "include extension ${ext}" OFF)
  endif()
endforeach()

if(NOT CPACK_GENERATOR)
  if(WIN32)
     set(CPACK_GENERATER ZIP)
  else()
     set(CPACK_GENERATOR TGZ)
  endif()
endif()

set(PACKAGE_COMMANDS "")
foreach(ext IN LISTS extensions)
  if (EXT_${ext})
      add_subdirectory(${ext})
      set(PACKAGE_COMMANDS ${PACKAGE_COMMANDS} COMMAND cpack -G ${CPACK_GENERATOR} --config ${ext}.cpack)
  endif()
endforeach()

if(PACKAGE_COMMANDS STREQUAL "")
   message(FATAL_ERROR "No extensions were specificed use -DENABLE_ALL_EXT=true or specify any of the following -DEXT_[${extensions}]=on ...")
endif()

add_custom_target(packages ${PACKAGE_COMMANDS})
add_custom_target(docs lua gen_gh_pages.lua WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
