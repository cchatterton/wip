#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

swift scripts/make-brand-assets.swift

iconset="$project_dir/assets/brand/WIP.iconset"
mkdir -p "$iconset"
master="$project_dir/assets/brand/WIPIcon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
done
sips -z 32 32 "$master" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 64 64 "$master" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 256 256 "$master" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 512 512 "$master" --out "$iconset/icon_256x256@2x.png" >/dev/null
cp "$master" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$project_dir/assets/brand/WIP.icns"
