#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/Startle.app" >&2
    exit 64
fi

app_path=$1

if [ ! -d "$app_path" ] || [ ! -f "$app_path/Contents/Info.plist" ]; then
    echo "Not a macOS application bundle: $app_path" >&2
    exit 66
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
"$script_dir/verify-unsigned-build.sh" "$app_path"

echo "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Inspecting signing details"
signing_details=$(codesign --display --verbose=4 "$app_path" 2>&1)
printf '%s\n' "$signing_details"

if ! printf '%s\n' "$signing_details" | grep -q 'Authority=Developer ID Application:'; then
    echo "The app is not signed with a Developer ID Application certificate." >&2
    exit 70
fi

if ! printf '%s\n' "$signing_details" | grep -q 'flags=.*runtime'; then
    echo "The app signature does not enable Hardened Runtime." >&2
    exit 70
fi

entitlements_path=$(mktemp -t startle-entitlements)
trap 'rm -f "$entitlements_path"' EXIT HUP INT TERM
codesign --display --entitlements :- "$app_path" 2>/dev/null > "$entitlements_path"

if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_path")" != "true" ]; then
    echo "The app signature does not contain the App Sandbox entitlement." >&2
    exit 70
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-only' "$entitlements_path")" != "true" ]; then
    echo "The app signature does not limit user-selected files to read-only access." >&2
    exit 70
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name:0' "$entitlements_path")" != "com.startle.app-spks" ]; then
    echo "The app signature does not allow communication with Sparkle's status service." >&2
    exit 70
fi

if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name:1' "$entitlements_path")" != "com.startle.app-spki" ]; then
    echo "The app signature does not allow communication with Sparkle's installer service." >&2
    exit 70
fi

echo "Checking Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "$app_path"

echo "Checking stapled notarization ticket"
xcrun stapler validate "$app_path"

echo "Checking privacy manifest"
plutil -lint "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"

echo "Distribution verification passed"
