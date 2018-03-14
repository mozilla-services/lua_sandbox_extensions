ARG EXTENSIONS="-DEXT_bloom_filter=true -DEXT_circular_buffer=true -DEXT_cjson=true \
    -DEXT_compat=true -DEXT_cuckoo_filter=true -DEXT_elasticsearch=true \
    -DEXT_hindsight=true -DEXT_heka=true -DEXT_hyperloglog=true -DEXT_lfs=true \
    -DEXT_lpeg=true -DEXT_lsb=true -DEXT_maxminddb=true -DEXT_moz_ingest=true \
    -DEXT_moz_telemetry=true -DEXT_openssl=true -DEXT_postgres=true -DEXT_rjson=true \
    -DEXT_rjson=true -DEXT_sax=true -DEXT_socket=true -DEXT_ssl=true \
    -DEXT_struct=true -DEXT_syslog=true -DEXT_zlib=true -DEXT_moz_security=true \
    -DEXT_aws=true"

FROM centos:7
ARG EXTENSIONS

RUN yum makecache
# Install some dependencies for LSB and hindsight build
RUN yum install -y git rpm-build c-compiler make curl gcc gcc-c++

WORKDIR /root
RUN curl -OL https://cmake.org/files/v3.10/cmake-3.10.2-Linux-x86_64.tar.gz
RUN cd /usr && \
    tar --strip-components=1 -zxf /root/cmake-3.10.2-Linux-x86_64.tar.gz

# We want to install lua_sandbox_extensions and hindsight as dependencies here
RUN git clone https://github.com/mozilla-services/lua_sandbox
RUN git clone https://github.com/mozilla-services/hindsight
RUN mkdir -p lua_sandbox/release && cd lua_sandbox/release && \
    cmake -DCMAKE_BUILD_TYPE=release .. && \
    make && ctest && cpack -G RPM && rpm -i *.rpm
RUN mkdir -p hindsight/release && cd hindsight/release && \
    cmake -DCMAKE_BUILD_TYPE=release .. && \
    make && ctest && cpack -G RPM && rpm -i *.rpm

# Required for maxminddb
RUN yum install -y epel-release
RUN yum install -y libmaxminddb-devel libmaxminddb

# Required for AWS
RUN curl -OL https://hsadmin.trink.com/packages/centos7/external/awssdk-1.3.7-1.x86_64.rpm
RUN rpm -i awssdk-1.3.7-1.x86_64.rpm

# Install dependencies for LSB extensions build
RUN yum install -y zlib-devel openssl-devel postgresql-devel libcurl-devel

RUN git clone https://github.com/trink/streaming_algorithms.git
RUN mkdir -p streaming_algorithms/release && cd streaming_algorithms/release && \
    cmake -DCMAKE_BUILD_TYPE=release -DCPACK_GENERATOR=RPM .. && \
    make && ctest && make packages && rpm -i *.rpm

ADD . /root/lua_sandbox_extensions
RUN mkdir -p lua_sandbox_extensions/release && cd lua_sandbox_extensions/release && \
    cmake -DCMAKE_BUILD_TYPE=release -DCPACK_GENERATOR=RPM \
    ${EXTENSIONS} .. && \
    make && ctest -V && make packages && rpm -i *.rpm
