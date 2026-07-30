#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 /path/to/Startle.app /path/to/output asset-name" >&2
    exit 64
fi

app_path=$1
output_dir=$2
asset_name=$3

if [ ! -d "$app_path" ] || [ ! -f "$app_path/Contents/Info.plist" ]; then
    echo "Not a macOS application bundle: $app_path" >&2
    exit 66
fi

case "$asset_name" in
    */* | "")
        echo "The asset name must be a non-empty file name without slashes." >&2
        exit 64
        ;;
esac

mkdir -p "$output_dir"
output_dir=$(CDPATH= cd "$output_dir" && pwd)
archive_name="$asset_name.zip"
dmg_name="$asset_name.dmg"
archive_path="$output_dir/$archive_name"
dmg_path="$output_dir/$dmg_name"
staging_root=$(mktemp -d "${TMPDIR:-/tmp}/startle-release.XXXXXX")
staging_dir="$staging_root/Startle"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/Startle.app"
ln -s /Applications "$staging_dir/Applications"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
hdiutil create \
    -volname Startle \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 "$archive_name" > "$archive_name.sha256"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

echo "Packaged $archive_path"
echo "Packaged $dmg_path"
