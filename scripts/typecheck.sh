#!/bin/sh
# Type-checks the whole app with the bare Swift toolchain (no Xcode needed).
# SwiftData macros are replaced by the shim in Models/Persistence.swift and
# the target is macOS, so iOS-only APIs are excluded with #if os(iOS).
set -e
cd "$(dirname "$0")/.."
xcrun swiftc -typecheck \
  -swift-version 5 \
  -target arm64-apple-macos15.0 \
  -parse-as-library \
  -D SWIFTDATA_SHIM \
  $(find MacroLog -name '*.swift') "$@"
echo "typecheck OK"
