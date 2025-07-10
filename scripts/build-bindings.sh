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

# Tweak the Swift import
SWIFT_FILE="$SWIFT_DIR/polkabind.swift"
if [[ -f "$SWIFT_FILE" ]]; then
  sed -i '' '1s%^%@_implementationOnly import PolkabindFFI\n%' "$SWIFT_FILE"
  sed -i '' '/^import polkabind$/d'    "$SWIFT_FILE"
fi

echo "✅ Swift bindings are in $SWIFT_DIR"

echo "🛠️ Creating the XCFramework .."

DEVICE_LIB=target/aarch64-apple-ios/release/libpolkabind.dylib
cargo build --release --target aarch64-apple-ios

SIM_LIB=target/x86_64-apple-ios/release/libpolkabind.dylib
cargo build --release --target x86_64-apple-ios

echo "🧹 Cleaning old XCFramework .."

XCF_ROOT_DIR="$ROOT/out/PolkabindSwift"
XCF_DIR="$ROOT/out/PolkabindSwift/Polkabind.xcframework"
rm -rf "$XCF_DIR"

xcodebuild -create-xcframework \
\
-library "$DEVICE_LIB" \
-headers bindings/swift \
\
-library "$SIM_LIB" \
-headers bindings/swift \
\
-output out/PolkabindSwift/Polkabind.xcframework

echo "🛠 Building Swift XCFramework .."

rm "$XCF_ROOT_DIR/sources/Polkabind/polkabind.swift"
cp "$SWIFT_DIR/polkabind.swift" "$XCF_ROOT_DIR/sources/Polkabind/"

cd "$XCF_ROOT_DIR"
swift build

echo "✅ Done building Swift XCFramework."
