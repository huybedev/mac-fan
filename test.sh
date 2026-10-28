#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build=$(mktemp -d "${TMPDIR:-/tmp}/macfan-tests.XXXXXX")
trap '/bin/rm -rf "$build"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/MacFanSwiftModuleCache" Sources/Models.swift Sources/SMC.swift Sources/Controller.swift Sources/Localization.swift Tests/Tests.swift -o "$build/tests" -framework IOKit
"$build/tests"
/bin/bash -n Resources/install-helper.sh Resources/uninstall-helper.sh build.sh
/usr/bin/plutil -lint Resources/Info.plist Resources/vn.huytran.MacFan.Helper.plist
