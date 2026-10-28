#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
destination=${1:-..}
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
app="$destination/MacFan.app"
build=$(mktemp -d "${TMPDIR:-/tmp}/macfan-build.XXXXXX")
trap '/bin/rm -rf "$build"' EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
common=(-swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "${TMPDIR:-/tmp}/MacFanSwiftModuleCache")
xcrun swiftc "${common[@]}" Sources/Models.swift Sources/SMC.swift Sources/Controller.swift Sources/Helper.swift -o "$app/Contents/Resources/MacFanHelper" -framework IOKit -framework Security
/usr/bin/codesign --force --sign - --options runtime --identifier vn.huytran.MacFan.Helper "$app/Contents/Resources/MacFanHelper"
hash=$(/usr/bin/codesign -dv --verbose=4 "$app/Contents/Resources/MacFanHelper" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
printf 'identifier "vn.huytran.MacFan.Helper" and cdhash H"%s"\n' "$hash" > "$app/Contents/Resources/helper-requirement.txt"
/usr/bin/codesign --verify --strict -R "=$(cat "$app/Contents/Resources/helper-requirement.txt")" "$app/Contents/Resources/MacFanHelper"
xcrun swiftc "${common[@]}" Sources/Models.swift Sources/SMC.swift Sources/Localization.swift Sources/AppModel.swift Sources/Integration.swift Sources/MacFanApp.swift -o "$app/Contents/MacOS/MacFan" -framework SwiftUI -framework Charts -framework IOKit -framework ServiceManagement -framework AppKit
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/*.sh Resources/vn.huytran.MacFan.Helper.plist Resources/Stats-LICENSE.txt "$app/Contents/Resources/"
cp Resources/MacFan.icns "$app/Contents/Resources/MacFan.icns"
/usr/bin/codesign --force --sign - --options runtime --identifier vn.huytran.MacFan "$app"
/usr/bin/codesign --verify --deep --strict "$app"
hash=$(/usr/bin/codesign -dv --verbose=4 "$app/Contents/MacOS/MacFan" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
/usr/bin/codesign --verify --strict -R "=identifier \"vn.huytran.MacFan\" and cdhash H\"$hash\"" "$app"
printf 'Built: %s\n' "$app"
