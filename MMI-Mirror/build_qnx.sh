#!/bin/sh
set -eu

QNX_HOST="${QNX_HOST:-/usr/qnx650/host/qnx6/x86}"
QNX_TARGET="${QNX_TARGET:-/usr/qnx650/target/qnx6}"
export QNX_HOST QNX_TARGET

CC="${CC:-$QNX_HOST/usr/bin/ntoarmv7-gcc}"
export CC

if [ ! -x "$CC" ]; then
    echo "ERROR: QNX ARMv7 gcc driver not found: $CC" >&2
    echo "Set QNX_HOST/QNX_TARGET or CC before running this script." >&2
    exit 1
fi

make clean
make

BIN="build/mmi-mirror-display"
file "$BIN" 2>/dev/null || true
ls -lh "$BIN"

READELF="$QNX_HOST/usr/bin/ntoarmv7-readelf"
if [ -x "$READELF" ]; then
    if "$READELF" -d "$BIN" | grep -q 'libstdc++'; then
        echo "ERROR: unexpected libstdc++ dependency remains" >&2
        exit 1
    fi
    echo "Dependency check OK: no libstdc++.so dependency."
fi
