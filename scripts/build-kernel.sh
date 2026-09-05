#!/bin/sh
set -eu
: "${CLANG_DIR:?path to proton-clang}"
: "${ANYKERNEL_DIR:?path to an Anykernel3-tissot checkout}"
: "${JOBS:=$(nproc)}"
zip=$PWD/dist/perf++-v1.1-tissot-$(date +%Y%m%d-%H%M).zip

export PATH=$CLANG_DIR/bin:$PATH
make O=out ARCH=arm64 tissot_defconfig
make O=out ARCH=arm64 -j"$JOBS" CC=clang \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r "$ANYKERNEL_DIR"/. "$tmp"
rm -rf "$tmp/.git"
cp out/arch/arm64/boot/Image.gz-dtb "$tmp"
mkdir -p dist
(cd "$tmp" && zip -qr9 "$zip" .)
echo "$zip"
