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

if [ ! -x "$executable_path" ]; then
    echo "The application executable is missing: $executable_path" >&2
    exit 66
fi

if [ ! -x "$framework_executable" ]; then
    echo "The embedded StartleCore framework is missing or incomplete." >&2
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

app_architectures=$(lipo -archs "$executable_path")
framework_architectures=$(lipo -archs "$framework_executable")
for architecture in arm64 x86_64; do
    case " $app_architectures " in
        *" $architecture "*) ;;
        *) echo "The application is missing the $architecture architecture." >&2; exit 70 ;;
    esac
    case " $framework_architectures " in
        *" $architecture "*) ;;
        *) echo "StartleCore.framework is missing the $architecture architecture." >&2; exit 70 ;;
    esac
done

plutil -lint "$info_plist"
plutil -lint "$app_path/Contents/Resources/PrivacyInfo.xcprivacy"

echo "Unsigned bundle verification passed"
