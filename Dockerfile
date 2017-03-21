FROM stefaniuk/ubuntu:16.04-20170320

# SEE: http://www.linuxfromscratch.org/lfs/view/8.0-systemd/

ARG APT_PROXY
ARG APT_PROXY_SSL

ARG LFS_TEST=1
ARG PROC=1
ENV LFS=/mnt/lfs

# 2.2
COPY assets/usr/local/bin /usr/local/bin
RUN set -x && \
    /usr/local/bin/prepare.sh && \
    /usr/local/bin/check-version.sh && \
    /usr/local/bin/check-library.sh

# 3.1
COPY assets/mnt/lfs/sources $LFS/sources
WORKDIR $LFS/sources
RUN set -x && \
    chmod -v a+wt $LFS/sources && \
    wget --input-file=wget-list --continue --timestamping && \
    md5sum -c md5sums

# 4.2
RUN set -x && \
    mkdir -pv $LFS/tools && \
    ln -fsv $LFS/tools /

# 4.3
RUN set -x && \
    groupadd lfs && \
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs && \
    echo "lfs:lfs" | chpasswd && \
    chown -v lfs $LFS/tools && \
    chown -v lfs $LFS/sources
USER lfs

# 4.4
COPY assets/home/lfs /home/lfs

# 4.5
ENV \
    LC_ALL=POSIX \
    LFS_TGT=x86_64-lfs-linux-gnu \
    PATH=/tools/bin:/bin:/usr/bin \
    MAKEFLAGS="-j 2"

# TODO: Build stuff

USER root
RUN set -x && \
    chown -R root:root $LFS/tools
ENV \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin:/root/usr/bin

### METADATA ###################################################################

ARG VERSION
ARG BUILD_DATE
ARG VCS_REF
ARG VCS_URL
LABEL \
    version=$VERSION \
    build-date=$BUILD_DATE \
    vcs-ref=$VCS_REF \
    vcs-url=$VCS_URL \
    license="MIT"
