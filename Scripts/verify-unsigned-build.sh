#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/Startle.app" >&2
    exit 64
fi

app_path=$1
info_plist="$app_path/Contents/Info.plist"

if [ ! -d "$app_path" ] || [ ! -f "$info_plist" ]; then
    echo "Not a macOS application bundle: $app_path" >&2
    exit 66
fi

executable_name=$(plutil -extract CFBundleExecutable raw -o - "$info_plist")
executable_path="$app_path/Contents/MacOS/$executable_name"
framework_path="$app_path/Contents/Frameworks/StartleCore.framework"
framework_executable="$framework_path/Versions/A/StartleCore"
sparkle_framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
sparkle_executable="$sparkle_framework_path/Versions/B/Sparkle"

if [ ! -x "$executable_path" ]; then
    echo "The application executable is missing: $executable_path" >&2
    exit 66
fi

if [ ! -x "$framework_executable" ]; then
    echo "The embedded StartleCore framework is missing or incomplete." >&2
    exit 66
fi

if [ ! -x "$sparkle_executable" ]; then
    echo "The embedded Sparkle framework is missing or incomplete." >&2
    exit 66
fi

if [ ! -d "$sparkle_framework_path/Versions/B/XPCServices/Installer.xpc" ]; then
    echo "Sparkle's installer service is missing from the sandboxed app." >&2
    exit 66
fi

if [ ! -d "$sparkle_framework_path/Versions/B/XPCServices/Downloader.xpc" ]; then
    echo "Sparkle's downloader service is missing from the sandboxed app." >&2
    exit 66
fi

if ! otool -l "$executable_path" | grep -q '@executable_path/../Frameworks'; then
    echo "The application does not search its embedded Frameworks directory." >&2
    exit 70
fi

if ! otool -L "$executable_path" | grep -q '@rpath/StartleCore.framework/Versions/A/StartleCore'; then
    echo "The application is not linked to the expected StartleCore framework." >&2
    exit 70
fi

if ! otool -L "$executable_path" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
    echo "The application is not linked to the expected Sparkle framework." >&2
    exit 70
fi

if [ "$(plutil -extract SUEnableInstallerLauncherService raw -o - "$info_plist")" != "true" ]; then
    echo "Sparkle's installer service is not enabled in Info.plist." >&2
    exit 70
fi

if [ "$(plutil -extract SUEnableDownloaderService raw -o - "$info_plist")" != "true" ]; then
    echo "Sparkle's downloader service is not enabled in Info.plist." >&2
    exit 70
fi

if [ -z "$(plutil -extract SUFeedURL raw -o - "$info_plist")" ]; then
    echo "The Sparkle update feed URL is missing from Info.plist." >&2
    exit 70
fi

public_key=$(plutil -extract SUPublicEDKey raw -o - "$info_plist")
if [ -z "$public_key" ] || [ "$public_key" = "SPARKLE_PUBLIC_KEY" ]; then
    echo "The Sparkle public signing key is missing from Info.plist." >&2
    exit 70
fi

app_architectures=$(lipo -archs "$executable_path")
framework_architectures=$(lipo -archs "$framework_executable")
sparkle_architectures=$(lipo -archs "$sparkle_executable")
for architecture in arm64 x86_64; do
    case " $app_architectures " in
        *" $architecture "*) ;;
        *) echo "The application is missing the $architecture architecture." >&2; exit 70 ;;
    esac
    case " $framework_architectures " in
        *" $architecture "*) ;;
        *) echo "StartleCore.framework is missing the $architecture architecture." >&2; exit 70 ;;
    esac
    case " $sparkle_architectures " in
        *" $architecture "*) ;;
        *) echo "Sparkle.framework is missing the $architecture architecture." >&2; exit 70 ;;
    esac
done

plutil -lint "$info_plist"
plutil -lint "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"

echo "Unsigned bundle verification passed"
