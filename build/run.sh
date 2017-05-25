#!/bin/sh

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Author: Mathieu Parent <math.parent@gmail.com>

set -e

hindsight_dir="$PWD"
lsb_dir="$(dirname "$hindsight_dir")/lua_sandbox"

if [ ! -d "$lsb_dir" ]; then
    (   set -x;
        git clone https://github.com/mozilla-services/lua_sandbox "$lsb_dir"
        git rev-parse HEAD
    )
fi

. "$lsb_dir/build/functions.sh"

if [ "$1" != "build" -o $# -ge 2 ]; then
    usage
    exit 1
fi

build_lua_sandbox_extensions() {
    local packages
    local cmake_args
    local ext
    packages="git c++-compiler"
    cmake_args="-DENABLE_ALL_EXT=true"
    for ext in bloom_filter circular_buffer cjson compat cuckoo_filter \
            elasticsearch geoip heka hyperloglog kafka lfs lpeg lsb moz_telemetry \
            openssl parquet postgres rjson sax snappy socket ssl struct syslog \
            systemd zlib; do
        case "$ext" in
            geoip)
                cmake_args="$cmake_args -DEXT_$ext=false"
                ;;
            kafka)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    # requires ubuntu 16.06 yakkety or greater for librdkafka 0.9.x
                    packages="$packages librdkafka-dev"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    # available from confluent http://docs.confluent.io/3.1.0/installation.html#rpm-packages-via-yum
                    packages="$packages librdkafka-devel"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            openssl)
                cmake_args="$cmake_args -DEXT_$ext=false"
                ;;
            parquet)
                cmake_args="$cmake_args -DEXT_$ext=false"
                ;;
            postgres)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    packages="$packages libpq-dev postgresql-server-dev-all"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    packages="$packages postgresql-devel"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            snappy)
                cmake_args="$cmake_args -DEXT_$ext=false"
                ;;
            ssl)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    packages="$packages libssl-dev"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    packages="$packages openssl-devel"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            systemd)
                cmake_args="$cmake_args -DEXT_$ext=false"
                ;;
            zlib)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    packages="$packages zlib1g-dev"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    packages="$packages zlib-devel"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
        esac
    done

    install_packages $packages
    (   set -x

        rm -rf ./release
        # From README.md:
        mkdir release
        cd release

        cmake -DCMAKE_BUILD_TYPE=release $cmake_args \
            "-DCPACK_GENERATOR=${CPACK_GENERATOR}" ..
        make

        ctest -V
        make packages
    )
}

build_function="build_lua_sandbox_extensions"
main
