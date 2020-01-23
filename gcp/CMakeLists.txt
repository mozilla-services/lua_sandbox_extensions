# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.6)
project(gcp VERSION 0.0.9 LANGUAGES C CXX)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "GCP Lua Modules")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "luasandbox-lpeg (>= 1.0.15)")
string(REGEX REPLACE "[()]" "" CPACK_RPM_PACKAGE_REQUIRES ${CPACK_DEBIAN_PACKAGE_DEPENDS})

find_package(PkgConfig)
pkg_check_modules(GRPC REQUIRED IMPORTED_TARGET protobuf grpc++ grpc)

set(GOOGLE_APIS_DIR "/usr/local/include")
include_directories(${GOOGLE_APIS_DIR})

set(GOOGLE_SRCS
  ${GOOGLE_APIS_DIR}/google/api/annotations.pb.cc
  ${GOOGLE_APIS_DIR}/google/api/http.pb.cc
  ${GOOGLE_APIS_DIR}/google/api/label.pb.cc
  ${GOOGLE_APIS_DIR}/google/api/monitored_resource.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/type/http_request.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/type/log_severity.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/v2/log_entry.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/v2/log_entry.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/v2/logging.grpc.pb.cc
  ${GOOGLE_APIS_DIR}/google/logging/v2/logging.pb.cc
  ${GOOGLE_APIS_DIR}/google/pubsub/v1/pubsub.grpc.pb.cc
  ${GOOGLE_APIS_DIR}/google/pubsub/v1/pubsub.pb.cc
  ${GOOGLE_APIS_DIR}/google/rpc/status.pb.cc
)

foreach(SRC IN LISTS GOOGLE_SRCS)
  set_source_files_properties(${SRC} PROPERTIES COMPILE_FLAGS -Wno-unused-parameter)
endforeach()

set(MODULE_SRCS
  common.cpp
  logging.cpp
  pubsub.cpp
  ${GOOGLE_SRCS}
  gcp.def
)
set(INSTALL_MODULE_PATH ${INSTALL_IOMODULE_PATH})
set(TEST_CONFIGURATION "gcp")
include(sandbox_module)

target_link_libraries(gcp ${GRPC_STATIC_LIBRARIES})
set(GRPC_SHARE_DIR ${CMAKE_INSTALL_DATAROOTDIR}/luasandbox/grpc)
install(FILES /usr/local/share/grpc/roots.pem DESTINATION ${GRPC_SHARE_DIR})
