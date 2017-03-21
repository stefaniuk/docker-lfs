#!/bin/bash
set -ex

ln -sfv /bin/bash /bin/sh

apt-get --yes update
apt-get --yes install \
    bison \
    build-essential \
    gawk \
    texinfo \
    wget
#apt-get --yes install \
#    libgmp10 \
#    libmpc3 \
#    libmpfr4

rm -rf \
    /tmp/* \
    /var/tmp/* \
    /var/lib/apt/lists/* \
    /var/cache/apt/*
