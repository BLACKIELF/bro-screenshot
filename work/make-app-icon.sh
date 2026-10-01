#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ $# == 1 ]] || { echo 'Usage: bash make-app-icon.sh NEW_OUTPUT_DIRECTORY' >&2; exit 64; }
mkdir "$1" || { echo '拒绝覆盖已有图标构建目录。' >&2; exit 1; }
icon_build_dir=$(cd "$1" && pwd)
source_icon='assets/app-icon-1001v1.png'
test -f "$source_icon"
iconset="$icon_build_dir/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    /usr/bin/sips -z "$retina_size" "$retina_size" "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$iconset" --output "$icon_build_dir/AppIcon.icns"
echo "$icon_build_dir/AppIcon.icns"
