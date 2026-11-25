#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

swift build -c release --product WIP
"$project_dir/scripts/make-brand-assets.sh"

app_dir="$project_dir/dist/WIP.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/WIP" "$app_dir/Contents/MacOS/WIP"
chmod +x "$app_dir/Contents/MacOS/WIP"
cp "$project_dir/scripts/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/assets/brand/WIP.icns" "$app_dir/Contents/Resources/WIP.icns"
cp "$project_dir/assets/brand/WIPMark.png" "$app_dir/Contents/Resources/WIPMark.png"
cp "$project_dir/assets/brand/WIPIcon-1024.png" "$app_dir/Contents/Resources/WIPIcon-1024.png"
codesign --force --sign - "$app_dir"

print "$app_dir"
