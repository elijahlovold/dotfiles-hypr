#!/bin/sh
# Compile each spoke shader to the .qsb that Helix.qml / Tesla.qml load:
# common.glsl (version, uniform block, helpers) + <name>.glsl. Rerun after
# editing any .glsl here; the .qsb files are committed so the shell needs
# no build step.
set -e
cd "$(dirname "$0")"
QSB=${QSB:-/usr/lib/qt6/bin/qsb}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for src in *.glsl; do
    name=${src%.glsl}
    [ "$name" = common ] && continue
    cat common.glsl "$src" > "$tmp/$name.frag"
    "$QSB" --qt6 -o "$name.frag.qsb" "$tmp/$name.frag"
    echo "built $name.frag.qsb"
done
