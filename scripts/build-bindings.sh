#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/bindings"

UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"

echo "🛠️  Building host dylib .."
# this will place libpolkabind.dylib in $ROOT/target/release
cargo build --manifest-path "$ROOT/Cargo.toml" --release

DYLIB="$ROOT/target/release/libpolkabind.dylib"
if [[ ! -f "$DYLIB" ]]; then
  echo "❌ could not find $DYLIB"
  exit 1
fi

SWIFT_DIR="$OUT_DIR/swift"

echo "🧹 Cleaning old bindings .."
rm -rf "$SWIFT_DIR"
mkdir -p "$SWIFT_DIR"

echo "🍎 Generating Swift bindings .."
"$UNIFFI_BIN" generate \
  --library "$DYLIB" \
  --language swift \
  --out-dir "$SWIFT_DIR" \

echo "✅ Swift bindings are in $SWIFT_DIR"

# ─── Force‐import the FFI module so RustBuffer, ForeignBytes, etc. are available ───
SWIFT_FILE="$SWIFT_DIR/polkabind.swift"
if [[ -f "$SWIFT_FILE" ]]; then
  # Insert the FFI import immediately after Foundation
  sed -i '' \
    's|^import Foundation|import Foundation\n@_implementationOnly import polkabindFFI|' \
    "$SWIFT_FILE"
fi

echo "🛠️ Creating framework bundles .."
TMP="$ROOT/out/PolkabindSwift/tmp-frameworks"
rm -rf "$TMP"
mkdir -p "$TMP/device" "$TMP/simulator"

# 1) Device slice
DEVICE_LIB=target/aarch64-apple-ios/release/libpolkabind.dylib
DEVICE_FWK="$TMP/device/polkabindFFI.framework"
mkdir -p "$DEVICE_FWK"/{Headers,Modules}
cp "$DEVICE_LIB" "$DEVICE_FWK/polkabindFFI"                              # binary must be named "polkabindFFI"
cp "$SWIFT_DIR/polkabindFFI.h"  "$DEVICE_FWK/Headers/"                  # header
cp "$SWIFT_DIR/polkabindFFI.modulemap" "$DEVICE_FWK/Modules/module.modulemap"
# patch modulemap for framework consumption
sed -i '' \
  's/^module polkabindFFI/framework module polkabindFFI/' \
  "$DEVICE_FWK/Modules/module.modulemap"

# 2) Simulator slice
SIM_LIB=target/x86_64-apple-ios/release/libpolkabind.dylib
SIM_FWK="$TMP/simulator/polkabindFFI.framework"
mkdir -p "$SIM_FWK"/{Headers,Modules}
cp "$SIM_LIB"   "$SIM_FWK/polkabindFFI"
cp "$SWIFT_DIR/polkabindFFI.h"  "$SIM_FWK/Headers/"
cp "$SWIFT_DIR/polkabindFFI.modulemap" "$SIM_FWK/Modules/module.modulemap"
# patch modulemap for framework consumption
sed -i '' \
  's/^module polkabindFFI/framework module polkabindFFI/' \
  "$SIM_FWK/Modules/module.modulemap"

echo "✅ Done Creating framework bundles."

echo "🛠️ Creating the XCFramework .."

cargo build --release --target aarch64-apple-ios
cargo build --release --target x86_64-apple-ios

echo "🧹 Cleaning old XCFramework .."

XCF_ROOT_DIR="$ROOT/out/PolkabindSwift"
XCF_DIR="$ROOT/out/PolkabindSwift/polkabindFFI.xcframework"
rm -rf "$XCF_DIR"

xcodebuild -create-xcframework \
  -framework "$TMP/device/polkabindFFI.framework" \
  -framework "$TMP/simulator/polkabindFFI.framework" \
  -output out/PolkabindSwift/polkabindFFI.xcframework

echo "🛠 Validating iOS integration with xcodebuild …"

# Copy the generated Swift glue into the package
cp "$SWIFT_DIR/polkabind.swift" "$XCF_ROOT_DIR/Sources/Polkabind"

cd "$XCF_ROOT_DIR"
# Clean any leftover builds
rm -rf ~/Library/Developer/Xcode/DerivedData/Polkabind-*

# Build the iOS simulator slice to make sure everything links
xcodebuild \
  -scheme Polkabind \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  BUILD_DIR=build \
  clean build

echo "✅ XCFramework is iOS-ready."
