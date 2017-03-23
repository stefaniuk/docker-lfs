FROM stefaniuk/ubuntu:16.04-20170320

# SEE: http://www.linuxfromscratch.org/lfs/view/8.0-systemd/

ARG APT_PROXY
ARG APT_PROXY_SSL
ARG PROC=4

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
    MAKEFLAGS="-j $PROC"

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
    make install && \
    chmod -v u+w /tools/lib/libtcl8.6.so && \
    make install-private-headers && \
    ln -sfv tclsh8.6 /tools/bin/tclsh && \
    popd && \
    rm -rf /tmp/tcl*

# 5.12 Expect
RUN set -x && \
    tar -xf $(ls -1 expect*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'expect*') && \
    cp -v configure{,.orig} && \
    sed 's:/usr/local/bin:/bin:' configure.orig > configure && \
    ./configure \
        --prefix=/tools \
        --with-tcl=/tools/lib \
        --with-tclinclude=/tools/include && \
    make && \
    make SCRIPTS="" install && \
    popd && \
    rm -rf /tmp/expect*

# 5.13 DejaGNU
RUN set -x && \
    tar -xf $(ls -1 dejagnu-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'dejagnu-*') && \
    ./configure --prefix=/tools && \
    make install && \
    popd && \
    rm -rf /tmp/dejagnu-*

# 5.14 Check
RUN set -x && \
    tar -xf $(ls -1 check-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'check-*') && \
    PKG_CONFIG= ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/check-*

# 5.15 Ncurses
RUN set -x && \
    tar -xf $(ls -1 ncurses-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'ncurses-*') && \
    sed -i s/mawk// configure && \
    ./configure \
        --prefix=/tools \
        --with-shared \
        --without-debug \
        --without-ada \
        --enable-widec \
        --enable-overwrite && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/ncurses-*

# 5.16 Bash
RUN set -x && \
    tar -xf $(ls -1 bash-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'bash-*') && \
    ./configure \
        --prefix=/tools \
        --without-bash-malloc && \
    make && \
    make install && \
    ln -sfv bash /tools/bin/sh && \
    popd && \
    rm -rf /tmp/bash-*

# 5.17 Bison
RUN set -x && \
    tar -xf $(ls -1 bison-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'bison-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/bison-*

# 5.18 Bzip2
RUN set -x && \
    tar -xf $(ls -1 bzip2-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'bzip2-*') && \
    make && \
    make PREFIX=/tools install && \
    popd && \
    rm -rf /tmp/bzip2-*

# 5.19 Coreutils
RUN set -x && \
    tar -xf $(ls -1 coreutils-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'coreutils-*') && \
    ./configure \
        --prefix=/tools \
        --enable-install-program=hostname && \
    make && \
    make install && \
    while [[ -e confdir3/confdir3 ]]; do mv confdir3/confdir3 confdir3a; rmdir confdir3; mv confdir3a confdir3; done; rmdir confdir3 && \
    popd && \
    rm -rf /tmp/coreutils-*

# 5.20 Diffutils
RUN set -x && \
    tar -xf $(ls -1 diffutils-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'diffutils-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/diffutils-*

# 5.21 File
RUN set -x && \
    tar -xf $(ls -1 file-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'file-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/file-*

# 5.22 Findutils
RUN set -x && \
    tar -xf $(ls -1 findutils-*.tar.gz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'findutils-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    while [[ -e confdir3/confdir3 ]]; do mv confdir3/confdir3 confdir3a; rmdir confdir3; mv confdir3a confdir3; done; rmdir confdir3 && \
    popd && \
    rm -rf /tmp/findutils-*

# 5.23 Gawk
RUN set -x && \
    tar -xf $(ls -1 gawk-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gawk-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/gawk-*

# 5.24 Gettext
RUN set -x && \
    tar -xf $(ls -1 gettext-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gettext-*') && \
    cd gettext-tools && \
    EMACS="no" ./configure \
        --prefix=/tools \
        --disable-shared && \
    make -C gnulib-lib && \
    make -C intl pluralx.c && \
    make -C src msgfmt && \
    make -C src msgmerge && \
    make -C src xgettext && \
    cp -v src/{msgfmt,msgmerge,xgettext} /tools/bin && \
    popd && \
    rm -rf /tmp/gettext-*

# 5.25 Grep
RUN set -x && \
    tar -xf $(ls -1 grep-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'grep-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/grep-*

# 5.26 Gzip
RUN set -x && \
    tar -xf $(ls -1 gzip-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'gzip-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/gzip-*

# 5.27 M4
RUN set -x && \
    tar -xf $(ls -1 m4-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'm4-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/m4-*

# 5.28 Make
RUN set -x && \
    tar -xf $(ls -1 make-*.tar.bz2) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'make-*') && \
    ./configure \
        --prefix=/tools \
        --without-guile && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/make-*

# 5.29 Patch
RUN set -x && \
    tar -xf $(ls -1 patch-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'patch-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/patch-*

# 5.30 Perl
RUN set -x && \
    tar -xf $(ls -1 perl-*.tar.bz2) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'perl-*') && \
    sh Configure -des -Dprefix=/tools -Dlibs=-lm && \
    make && \
    cp -v perl cpan/podlators/scripts/pod2man /tools/bin && \
    mkdir -pv /tools/lib/perl5/5.24.1 && \
    cp -Rv lib/* /tools/lib/perl5/5.24.1 && \
    popd && \
    rm -rf /tmp/perl-*

# 5.31 Sed
RUN set -x && \
    tar -xf $(ls -1 sed-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'sed-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/sed-*

# 5.32 Tar
RUN set -x && \
    tar -xf $(ls -1 tar-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'tar-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    while [[ -e confdir3/confdir3 ]]; do mv confdir3/confdir3 confdir3a; rmdir confdir3; mv confdir3a confdir3; done; rmdir confdir3 && \
    popd && \
    rm -rf /tmp/tar-*

# 5.33 Texinfo
RUN set -x && \
    tar -xf $(ls -1 texinfo-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'texinfo-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/texinfo-*

# 5.34 Util-linux
RUN set -x && \
    tar -xf $(ls -1 util-linux-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'util-linux-*') && \
    ./configure \
        --prefix=/tools \
        --without-python \
        --disable-makeinstall-chown \
        --without-systemdsystemunitdir \
        --enable-libmount-force-mountinfo \
        PKG_CONFIG="" && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/util-linux-*

# 5.35 Xz
RUN set -x && \
    tar -xf $(ls -1 xz-*.tar.xz) -C /tmp && \
    pushd $(find /tmp -maxdepth 1 -type d -iname 'xz-*') && \
    ./configure --prefix=/tools && \
    make && \
    make install && \
    popd && \
    rm -rf /tmp/xz-*

# 5.36 - stripping
RUN set -x && ( \
        strip --strip-debug /tools/lib/* || true; \
        /usr/bin/strip --strip-unneeded /tools/{,s}bin/* || true; \
        rm -rf /tools/{,share}/{info,man,doc}; \
    )

# 5.37 - changing ownership
USER root
RUN set -x && \
    chown -R root:root $LFS/tools

# set original PATH
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin:/root/usr/bin

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
