#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd "$script_dir/.." && pwd)
source_svg="$project_dir/Design/AppIconMaster.svg"
master_png="$project_dir/Design/AppIconMaster.png"
asset_dir="$project_dir/Sources/StartleApp/Resources/Assets.xcassets/AppIcon.appiconset"
icns_path="$project_dir/Design/Startle.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert is required to render the SVG icon master." >&2
    exit 69
fi

render_png() {
    size=$1
    destination=$2
    rsvg-convert --width "$size" --height "$size" --output "$destination" "$source_svg"
}

render_png 1024 "$master_png"
render_png 16 "$asset_dir/icon_16x16.png"
render_png 32 "$asset_dir/icon_16x16@2x.png"
render_png 32 "$asset_dir/icon_32x32.png"
render_png 64 "$asset_dir/icon_32x32@2x.png"
render_png 128 "$asset_dir/icon_128x128.png"
render_png 256 "$asset_dir/icon_128x128@2x.png"
render_png 256 "$asset_dir/icon_256x256.png"
render_png 512 "$asset_dir/icon_256x256@2x.png"
render_png 512 "$asset_dir/icon_512x512.png"
render_png 1024 "$asset_dir/icon_512x512@2x.png"

write_u32() {
    value=$1
    printf "\\$(printf '%03o' $(((value >> 24) & 255)))"
    printf "\\$(printf '%03o' $(((value >> 16) & 255)))"
    printf "\\$(printf '%03o' $(((value >> 8) & 255)))"
    printf "\\$(printf '%03o' $((value & 255)))"
}

icns_total=8
for png in \
    "$asset_dir/icon_16x16.png" \
    "$asset_dir/icon_32x32.png" \
    "$asset_dir/icon_32x32@2x.png" \
    "$asset_dir/icon_128x128.png" \
    "$asset_dir/icon_256x256.png" \
    "$asset_dir/icon_512x512.png" \
    "$asset_dir/icon_512x512@2x.png"
do
    png_size=$(wc -c < "$png" | tr -d ' ')
    icns_total=$((icns_total + png_size + 8))
done

{
    printf 'icns'
    write_u32 "$icns_total"
    for entry in \
        "icp4:$asset_dir/icon_16x16.png" \
        "icp5:$asset_dir/icon_32x32.png" \
        "icp6:$asset_dir/icon_32x32@2x.png" \
        "ic07:$asset_dir/icon_128x128.png" \
        "ic08:$asset_dir/icon_256x256.png" \
        "ic09:$asset_dir/icon_512x512.png" \
        "ic10:$asset_dir/icon_512x512@2x.png"
    do
        type=${entry%%:*}
        png=${entry#*:}
        png_size=$(wc -c < "$png" | tr -d ' ')
        printf '%s' "$type"
        write_u32 $((png_size + 8))
        cat "$png"
    done
} > "$icns_path"

echo "Generated the Startle app icon assets."
