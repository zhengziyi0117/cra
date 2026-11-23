#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cra-chatgpt-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
app="$tmp/Test.app"
scripts/package-chatgpt.sh "$app"
codesign --force --sign - --options runtime --entitlements resources/CraMaxNode.entitlements "$app/Contents/MacOS/CraMaxNode"
node Tests/ChatGPTMaxTests.mjs "$app"
xcrun swiftc -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} Sources/Cra/Services/ChatGPTMax.swift Tests/ChatGPTMaxTests.swift -o "$tmp/max-tests"
"$tmp/max-tests" "$app"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$tmp/max-tests" "$CRA_TEST_KEEP/"
