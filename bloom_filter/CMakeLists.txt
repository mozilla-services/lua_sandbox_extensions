# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.0)
project(bloom-filter VERSION 1.0.0 LANGUAGES C)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lua bloom filter module (membership test)")
set(MODULE_SRCS bloom_filter.c ../common/xxhash.c bloom_filter.def)
include(sandbox_module)
