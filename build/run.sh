#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Author: Mathieu Parent <math.parent@gmail.com>

set -e

root_dir="$PWD"
lsb_dir="$(dirname "$root_dir")/lua_sandbox"
hs_dir="$(dirname "$root_dir")/hindsight"

if [ ! -d "$lsb_dir" ]; then
    (   set -x;
        git clone https://github.com/mozilla-services/lua_sandbox "$lsb_dir"
        git rev-parse HEAD
    )
fi

if [ ! -d "$hs_dir" ]; then
    (   set -x;
        git clone https://github.com/mozilla-services/hindsight "$hs_dir"
        git rev-parse HEAD
    )
fi

. "$lsb_dir/build/functions.sh"

if [ "$1" != "build" -o $# -ge 2 ]; then
    usage
    exit 1
fi

build_lua_sandbox_extensions() {
    if [[ "$DISTRO" =~ ^(centos:7|fedora:latest|ubuntu:latest) ]]; then
        integration_tests="true"
    fi

    echo "+cd $hs_dir"
    cd "$hs_dir"
    build
    if [ "$DISTRO" = "fedora:latest" ]; then
        (   set -x;
            $as_root yum install -y lua
        )
    fi
    install_packages_from_dir ./release
    echo "+cd $root_dir"
    cd "$root_dir"

    local packages
    local cmake_args
    local ext
    packages="git c++-compiler"
    cmake_args=""
    # todo add support for aws jose kafka parquet systemd moz_pioneer moz_security
    for ext in bloom_filter circular_buffer cjson compat cuckoo_filter \
            elasticsearch hindsight heka hyperloglog lfs lpeg lsb maxminddb \
            moz_ingest moz_telemetry openssl postgres rjson sax socket ssl \
            struct syslog zlib; do
        case "$ext" in
            maxminddb)
                if [ "$integration_tests" = "true" ]; then
                    if [ "$CPACK_GENERATOR" = "DEB" ]; then
                        (   set -x;
                            $as_root apt-get install -y software-properties-common
                            $as_root add-apt-repository -y ppa:maxmind/ppa
                        )
                        packages="$packages libmaxminddb-dev libmaxminddb0"
                        cmake_args="$cmake_args -DEXT_$ext=true"
                    elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                        if [[ "$DISTRO" =~ ^centos ]]; then
                            (   set -x;
                                $as_root yum install -y "epel-release"
                            )
                        fi
                        packages="$packages libmaxminddb-devel libmaxminddb"
                        cmake_args="$cmake_args -DEXT_$ext=true"
                    else
                        cmake_args="$cmake_args -DEXT_$ext=false"
                    fi
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            postgres)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    packages="$packages libpq-dev postgresql-server-dev-all"
                    cmake_args="$cmake_args -DEXT_$ext=false"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    packages="$packages postgresql-devel"
                    cmake_args="$cmake_args -DEXT_$ext=false"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            *ssl)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
		    if [ -f "/etc/debian_version" ] && egrep -q '(^9|^buster/sid)' /etc/debian_version; then
                        # Install older OpenSSL for stretch / ubuntu dev
                        packages="$packages libssl1.0-dev"
                    else
                        packages="$packages libssl-dev"
                    fi
                    cmake_args="$cmake_args -DEXT_$ext=true"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    if [ -f "/etc/redhat-release" ] && grep -q '^Fedora' /etc/redhat-release; then
			# Newer Fedora installs 1.1 by default, install the 1.0 compat package as well
                        packages="$packages compat-openssl10-devel"
                    else
                        packages="$packages openssl-devel"
                    fi
                    cmake_args="$cmake_args -DEXT_$ext=true"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            zlib)
                if [ "$CPACK_GENERATOR" = "DEB" ]; then
                    packages="$packages zlib1g-dev"
                    cmake_args="$cmake_args -DEXT_$ext=true"
                elif [ "$CPACK_GENERATOR" = "RPM" ]; then
                    packages="$packages zlib-devel"
                    cmake_args="$cmake_args -DEXT_$ext=true"
                else
                    cmake_args="$cmake_args -DEXT_$ext=false"
                fi
                ;;
            *)
                cmake_args="$cmake_args -DEXT_$ext=true";
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

    if [ "$integration_tests" = "true" ]; then
        (   set -x
            cd release
            install_packages_from_dir .
            ctest -V -C integration -j 10
        )
    fi
}

build_function="build_lua_sandbox_extensions"
main
