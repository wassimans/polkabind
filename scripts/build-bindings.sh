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

echo "🛠️ Creating the XCFramework .."

DEVICE_LIB=target/aarch64-apple-ios/release/libpolkabind.dylib
cargo build --release --target aarch64-apple-ios

SIM_LIB=target/x86_64-apple-ios/release/libpolkabind.dylib
cargo build --release --target x86_64-apple-ios

echo "🧹 Cleaning old XCFramework .."

XCF_ROOT_DIR="$ROOT/out/PolkabindSwift"
XCF_DIR="$ROOT/out/PolkabindSwift/polkabindFFI.xcframework"
rm -rf "$XCF_DIR"

xcodebuild -create-xcframework \
\
-library "$DEVICE_LIB" \
-headers bindings/swift \
\
-library "$SIM_LIB" \
-headers bindings/swift \
\
-output out/PolkabindSwift/polkabindFFI.xcframework

for arch in ios-arm64 ios-x86_64-simulator; do
  HDR="$XCF_DIR/$arch/Headers"
  # 1) Rename the module‐map so SwiftPM will see *any* modulemap at all
  mv "$HDR/polkabindFFI.modulemap" "$HDR/module.modulemap"
  # 2) Patch its contents to declare the module UniFFI’s Swift is expecting
  #sed -i '' 's/module polkabindFFI/module PolkabindFFI/' "$HDR/module.modulemap"
done

echo "🛠 Building Swift XCFramework .."

cd "$XCF_ROOT_DIR"
rm -rf .build
cp "$SWIFT_DIR/polkabind.swift" "$XCF_ROOT_DIR/Sources/Polkabind"
swift build

echo "✅ Done building Swift XCFramework."
