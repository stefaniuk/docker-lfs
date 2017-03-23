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
    ln -sfv $LFS/tools /tools

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

# 5.4 Binutils - Pass 1
RUN set -x && \
    tar -xf $(ls -1 binutils-*) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'binutils-*') && \
    mkdir -v build && \
    cd build && \
    time { \
        ../configure \
            --prefix=/tools \
            --with-sysroot=$LFS \
            --with-lib-path=/tools/lib \
            --target=$LFS_TGT \
            --disable-nls \
            --disable-werror && \
        make && \
        mkdir -pv /tools/lib && \
        ln -sfv lib /tools/lib64 && \
        make install && \
        popd && \
        rm -rf /tmp/binutils-*; \
    }

# 5.5 GCC - Pass 1
RUN set -x && \
    tar -xf $(ls -1 gcc-*) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gcc-*') && \
    tar -xf $LFS/sources/mpfr-3.1.5.tar.xz && \
    mv -v mpfr-3.1.5 mpfr && \
    tar -xf $LFS/sources/gmp-6.1.2.tar.xz && \
    mv -v gmp-6.1.2 gmp && \
    tar -xf $LFS/sources/mpc-1.0.3.tar.gz && \
    mv -v mpc-1.0.3 mpc && \
    for file in gcc/config/{linux,i386/linux{,64}}.h; do \
        cp -uv $file{,.orig}; \
        sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' -e 's@/usr@/tools@g' $file.orig > $file; \
        echo -e "\n#undef STANDARD_STARTFILE_PREFIX_1\n#undef STANDARD_STARTFILE_PREFIX_2\n#define STANDARD_STARTFILE_PREFIX_1 \"/tools/lib/\"\n#define STANDARD_STARTFILE_PREFIX_2 \"\"" >> $file; \
        touch $file.orig; \
    done && \
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 && \
    mkdir -v build && \
    cd build && \
    ../configure \
        --target=$LFS_TGT \
        --prefix=/tools \
        --with-glibc-version=2.11 \
        --with-sysroot=$LFS \
        --with-newlib \
        --without-headers \
        --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include \
        --disable-nls \
        --disable-shared \
        --disable-multilib \
        --disable-decimal-float \
        --disable-threads \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libmpx \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libvtv \
        --disable-libstdcxx \
        --enable-languages=c,c++ && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/gcc-*

# 5.6 Linux API Headers
RUN set -x && \
    tar -xf $(ls -1 linux-*) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'linux-*') && \
    make mrproper && \
    make INSTALL_HDR_PATH=dest headers_install && \
    cp -rv dest/include/* /tools/include && \
    popd && \
    rm -rf /tmp/linux-*

# 5.7 Glibc
RUN set -x && \
    tar -xf $(ls -1 glibc-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'glibc-*') && \
    mkdir -v build && \
    cd build && \
    ../configure \
        --prefix=/tools \
        --host=$LFS_TGT \
        --build=$(../scripts/config.guess) \
        --enable-kernel=2.6.32 \
        --with-headers=/tools/include \
        libc_cv_forced_unwind=yes \
        libc_cv_c_cleanup=yes && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/glibc-*
RUN set -x && \
    echo 'int main(){}' > dummy.c && \
    $LFS_TGT-gcc dummy.c && \
    readelf -l a.out | grep ': /tools' && \
    rm -v dummy.c a.out

# 5.8 Libstdc++
RUN set -x && \
    tar -xf $(ls -1 gcc-*.tar.bz2) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gcc-*') && \
    mkdir -v build && \
    cd build && \
    ../libstdc++-v3/configure \
        --host=$LFS_TGT \
        --prefix=/tools \
        --disable-multilib \
        --disable-nls \
        --disable-libstdcxx-threads \
        --disable-libstdcxx-pch \
        --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/6.3.0 && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/gcc-*

# 5.9 Binutils - Pass 2
RUN set -x && \
    tar -xf $(ls -1 binutils-*.tar.bz2) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'binutils-*') && \
    mkdir -v build && \
    cd build && \
    CC=$LFS_TGT-gcc AR=$LFS_TGT-ar RANLIB=$LFS_TGT-ranlib ../configure \
        --prefix=/tools \
        --disable-nls \
        --disable-werror \
        --with-lib-path=/tools/lib \
        --with-sysroot && \
    make && \
    make install && \
    make -C ld clean && \
    make -C ld LIB_PATH=/usr/lib:/lib && \
    cp -v ld/ld-new /tools/bin && \
    popd && \
    rm -rf /tmp/binutils-*

# 5.10 GCC - Pass 2
RUN set -x && \
    tar -xf $(ls -1 gcc-*.tar.bz2) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gcc-*') && \
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h && \
    for file in gcc/config/{linux,i386/linux{,64}}.h; do \
        cp -uv $file{,.orig}; \
        sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' -e 's@/usr@/tools@g' $file.orig > $file; \
        echo -e "\n#undef STANDARD_STARTFILE_PREFIX_1 \n#undef STANDARD_STARTFILE_PREFIX_2 \n#define STANDARD_STARTFILE_PREFIX_1 \"/tools/lib/\" \n#define STANDARD_STARTFILE_PREFIX_2 \"\"" >> $file; \
        touch $file.orig; \
    done && \
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 && \
    tar -xf $LFS/sources/mpfr-3.1.5.tar.xz && \
    mv -v mpfr-3.1.5 mpfr && \
    tar -xf $LFS/sources/gmp-6.1.2.tar.xz && \
    mv -v gmp-6.1.2 gmp && \
    tar -xf $LFS/sources/mpc-1.0.3.tar.gz && \
    mv -v mpc-1.0.3 mpc && \
    mkdir -v build && \
    cd build && \
    CC=$LFS_TGT-gcc CXX=$LFS_TGT-g++ AR=$LFS_TGT-ar RANLIB=$LFS_TGT-ranlib ../configure \
        --prefix=/tools \
        --with-local-prefix=/tools \
        --with-native-system-header-dir=/tools/include \
        --enable-languages=c,c++ \
        --disable-libstdcxx-pch \
        --disable-multilib \
        --disable-bootstrap \
        --disable-libgomp && \
    make && \
    make install && \
    ln -sfv gcc /tools/bin/cc && \
    popd && \
    rm -rf /tmp/gcc-*
RUN set -x && \
    echo 'int main(){}' > dummy.c && \
    cc dummy.c && \
    readelf -l a.out | grep ': /tools' && \
    rm -v dummy.c a.out

# 5.11 Tcl-core
RUN set -x && \
    tar -xf $(ls -1 tcl-core*-src.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'tcl*') && \
    cd unix && \
    ./configure --prefix=/tools && \
    make && \
    TZ=UTC make test && \
    make install && \
    chmod -v u+w /tools/lib/libtcl8.6.so && \
    make install-private-headers && \
    ln -sfv tclsh8.6 /tools/bin/tclsh && \
    popd && \
    rm -rf /tmp/tcl*

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
