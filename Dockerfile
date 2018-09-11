ARG EXTENSIONS="-DENABLE_ALL_EXT=true"

FROM centos:7
ARG EXTENSIONS

WORKDIR /root

# Install most of our package dependencies here
RUN yum makecache && \
    yum install -y git rpm-build c-compiler make curl gcc gcc-c++ systemd-devel \
    autoconf automake centos-release-scl epel-release zlib-devel openssl-devel \
    postgresql-devel libcurl-devel lua-devel && \
    yum install -y https://packages.red-data-tools.org/centos/red-data-tools-release-1.0.0-1.noarch.rpm && \
    yum install -y libmaxminddb-devel jq libmaxminddb librdkafka-devel jansson-devel devtoolset-6 && \
    yum install -y --enablerepo=epel arrow-devel-0.9.0 && \
    curl -OL https://cmake.org/files/v3.10/cmake-3.10.2-Linux-x86_64.tar.gz && \
    if [[ `sha256sum cmake-3.10.2-Linux-x86_64.tar.gz | awk '{print $1}'` != \
        "7a82b46c35f4e68a0807e8dc04e779dee3f36cd42c6387fd13b5c29fe62a69ea" ]]; then exit 1; fi && \
    (cd /usr && tar --strip-components=1 -zxf /root/cmake-3.10.2-Linux-x86_64.tar.gz) && \
    curl -OL https://s3-us-west-2.amazonaws.com/net-mozaws-data-us-west-2-ops-ci-artifacts/mozilla-services/lua_sandbox_extensions/external/centos7/awssdk-1.3.7-1.x86_64.rpm && \
    if [[ `sha256sum awssdk-1.3.7-1.x86_64.rpm | awk '{print $1}'` != \
        "d78b164b774848d9b6adf99b59d2651832d3cfe52bae5727fb5afeb33eb13191" ]]; then exit 1; fi && \
    rpm -i awssdk-1.3.7-1.x86_64.rpm && \
    curl -OL https://s3-us-west-2.amazonaws.com/net-mozaws-data-us-west-2-ops-ci-artifacts/mozilla-services/lua_sandbox_extensions/external/centos7/parquet-cpp-1.3.1-1.x86_64.rpm && \
    if [[ `sha256sum parquet-cpp-1.3.1-1.x86_64.rpm | awk '{print $1}'` != \
        "7170c4d9d4bc114053ad8e59a2eb4b18ab54580d104179f1d53602f792513374" ]]; then exit 1; fi && \
    rpm -i parquet-cpp-1.3.1-1.x86_64.rpm && \
    cat /etc/yum.conf | grep -v override_install_langs > /etc/yum.conf.lang && \
    cp /etc/yum.conf.lang /etc/yum.conf && \
    yum reinstall -y glibc-common && \
    yum install -y stow && \
    curl -OL https://s3-us-west-2.amazonaws.com/net-mozaws-data-us-west-2-ops-ci-artifacts/mozilla-services/lua_sandbox_extensions/external/centos7/grpc_stow.tgz && \
    if [[ `sha256sum grpc_stow.tgz | awk '{print $1}'` != \
        "65dba4a11ccc09ced4dad64ef196cab6299736a5f5e0df83fef6f1046213797b" ]]; then exit 1; fi && \
    tar -C / -zxf grpc_stow.tgz && \
    stow -d /usr/local/stow protobuf-3 grpc googleapis

# Use devtoolset-6
ENV PERL5LIB='PERL5LIB=/opt/rh/devtoolset-6/root//usr/lib64/perl5/vendor_perl:/opt/rh/devtoolset-6/root/usr/lib/perl5:/opt/rh/devtoolset-6/root//usr/share/perl5/vendor_perl' \
    X_SCLS=devtoolset-6 \
    PCP_DIR=/opt/rh/devtoolset-6/root \
    LD_LIBRARY_PATH=/opt/rh/devtoolset-6/root/usr/lib64:/opt/rh/devtoolset-6/root/usr/lib \
    PATH=/opt/rh/devtoolset-6/root/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONPATH=/opt/rh/devtoolset-6/root/usr/lib64/python2.7/site-packages:/opt/rh/devtoolset-6/root/usr/lib/python2.7/site-packages \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Compile and install lua_sandbox and hindsight using master branch
RUN git clone https://github.com/mozilla-services/lua_sandbox && \
    git clone https://github.com/mozilla-services/hindsight && \
    mkdir -p lua_sandbox/release && cd lua_sandbox/release && \
    cmake -DCMAKE_BUILD_TYPE=release .. && \
    make && ctest && cpack -G RPM && rpm -i *.rpm && cd ../.. && \
    mkdir -p hindsight/release && cd hindsight/release && \
    cmake -DCMAKE_BUILD_TYPE=release .. && \
    make && ctest && cpack -G RPM && rpm -i *.rpm

# Compile some additional dependencies we need for lua_sandbox_extensions that we
# don't have packages for.
#
# cjose is required for jose, and right now the jose module requires 0.5.1
RUN git clone https://github.com/cisco/cjose.git && \
    cd cjose && git checkout tags/0.5.1 && \
    autoreconf && env CFLAGS='-g -O2 -I/usr/include/ -I/usr/include -fPIC' \
    ./configure --with-openssl=/usr --with-jansson=/usr  \
    --enable-static --disable-shared --prefix=/usr \
    && make && make install && cp cjose.pc /usr/lib64/pkgconfig/cjose.pc && cd .. && \
    git clone https://github.com/trink/streaming_algorithms.git && \
    mkdir -p streaming_algorithms/release && cd streaming_algorithms/release && \
    cmake -DCMAKE_BUILD_TYPE=release -DCPACK_GENERATOR=RPM .. && \
    make && ctest && make packages && rpm -i luasandbox*.rpm && cd ../.. && \
    git clone https://github.com/mozilla-services/mozilla-pipeline-schemas.git && \
    mkdir -p mozilla-pipeline-schemas/release && cd mozilla-pipeline-schemas/release && \
    cmake .. && make && cpack -G RPM && rpm -i *.rpm && cd ../.. && \
    git clone https://github.com/trink/lua_date.git && \
    mkdir -p lua_date/release && cd lua_date && \
    git submodule init && git submodule update && \
    cd release && \
    cmake -DCMAKE_BUILD_TYPE=release -DCPACK_GENERATOR=RPM .. && make && \
    ctest && make packages

# Add our extensions repo, build all of them, test and install the RPMs in the image
#
# As a final step here as well, place the RPMs generated from some of the external
# dependencies in the release directory with the lua_sandbox_extensions packages
ADD . /root/lua_sandbox_extensions
RUN mkdir -p lua_sandbox_extensions/release && cd lua_sandbox_extensions/release && \
    cmake -DCMAKE_BUILD_TYPE=release -DCPACK_GENERATOR=RPM \
    ${EXTENSIONS} .. && \
    make && ctest -V && make packages && \
    cp ../../lua_date/release/iana*rpm ../../lua_date/release/luasandbox*rpm . && \
    rpm -i *.rpm && \
    cp ../../streaming_algorithms/release/luasandbox-streaming-algorithms* . && \
    cp ../../hindsight/release/*.rpm . && \
    cp ../../lua_sandbox/release/*.rpm .

# Add a hindsight user and default RUN command
RUN groupadd hindsight && useradd -g hindsight -s /bin/bash -m hindsight
CMD /usr/bin/su - hindsight -c 'cd /home/hindsight && hindsight hindsight.cfg 7'
