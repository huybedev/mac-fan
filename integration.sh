#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app=${1:-/Applications/MacFan.app}
build=$(mktemp -d "${TMPDIR:-/tmp}/macfan-integration.XXXXXX")
trap '/bin/rm -rf "$build"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/MacFanSwiftModuleCache" Tests/UnauthorizedClient.swift -o "$build/unauthorized"
/usr/bin/codesign --force --sign - --identifier vn.huytran.MacFan.Unauthorized "$build/unauthorized"
"$build/unauthorized"
"$app/Contents/MacOS/MacFan" --integration-test
