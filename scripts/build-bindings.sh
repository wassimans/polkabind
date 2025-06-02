#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/core"
OUT_DIR="$ROOT/out/bindings"
ANDROID_APP="$ROOT/android/app"
IOS_APP="$ROOT/ios/speem"

# Rust artifacts
BINDGEN="$ROOT/target/release/uniffi-bindgen"
DYLIB="$ROOT/target/release/libpolkabind.dylib"
SO="$ROOT/target/release/libpolkabind.so"

KOTLIN_BINDINGS_DIR="$OUT_DIR/kotlin"
SWIFT_BINDINGS_DIR="$OUT_DIR/swift"

# helper: locate host cdylib
if [[ -f "$DYLIB" ]]; then
  HOST_LIB="$DYLIB"
elif [[ -f "$SO" ]]; then
  HOST_LIB="$SO"
else
  echo "❌ could not find polkabind.{dylib,so}"
  exit 1
fi

cmd=${1:-all}
shift || true

generate() {
  echo "🧹 Cleaning old bindings…"
  rm -rf "$KOTLIN_BINDINGS_DIR" "$SWIFT_BINDINGS_DIR"
  mkdir -p "$KOTLIN_BINDINGS_DIR" "$SWIFT_BINDINGS_DIR"

  echo "🛠️  Building core crate & uniffi-bindgen…"
  cargo build --manifest-path "$CORE_DIR/Cargo.toml" --bins --release

  [[ -x "$BINDGEN" ]] || { echo "❌ $BINDGEN missing"; exit 1; }

  echo "🔧 Generating Kotlin bindings…"
  "$BINDGEN" generate \
    --language kotlin \
    --library \
    --crate polkabind \
    --no-format \
    --out-dir "$KOTLIN_BINDINGS_DIR" \
    "$HOST_LIB"

  echo "🍎 Generating Swift bindings…"
  "$BINDGEN" generate \
    --language swift \
    --library \
    --crate polkabind \
    --out-dir "$SWIFT_BINDINGS_DIR" \
    "$HOST_LIB"

  # inject @_implementationOnly for polkabindFFI
  SWIFT_FILE="$SWIFT_BINDINGS_DIR/polkabind.swift"
  if [[ -f "$SWIFT_FILE" ]]; then
      # 1) Prepend the @_implementationOnly import
      sed -i '' '1s/^/@_implementationOnly import polkabindFFI\n/' "$SWIFT_FILE"
      # 2) Delete any normal import polkabindFFI lines
      sed -i '' '/^import polkabindFFI$/d' "$SWIFT_FILE"
  fi
}

# android_steps() {
#   echo "🤖 Cross-compiling Rust for Android ABIs…"
#   cargo ndk \
#     --output-dir "$ANDROID_APP/src/main/jniLibs" \
#     --target aarch64-linux-android \
#     --target armv7-linux-androideabi \
#     --target i686-linux-android \
#     --target x86_64-linux-android \
#     build -p speem --release

#   echo "🚀 Building & installing Android…"
#   ( cd "$ROOT/android" && chmod +x gradlew && ./gradlew installDebug )
# }

# ios_steps() {
#   echo "📦 Cross-compiling static Speem library for iOS…"

#   DEVICE="aarch64-apple-ios"
#   SIM="aarch64-apple-ios-sim"

#   for t in $DEVICE $SIM; do
#     echo "   • cargo build --release --target $t"
#     cargo build --manifest-path "$CORE_DIR/Cargo.toml" --release --target "$t"
#   done

#   DEV_LIB="$ROOT/target/$DEVICE/release/libspeem.a"
#   SIM_LIB="$ROOT/target/$SIM/release/libspeem.a"
#   for f in $DEV_LIB $SIM_LIB; do
#     [[ -f "$f" ]] || { echo "❌ Missing $f"; exit 1; }
#   done

#   mkdir -p "$SWIFT_BINDINGS_DIR/include"
#   cp "$SWIFT_BINDINGS_DIR"/speemFFI.h \
#      "$SWIFT_BINDINGS_DIR"/speemFFI.modulemap \
#      "$SWIFT_BINDINGS_DIR/include/"
#   mv "$SWIFT_BINDINGS_DIR/include/speemFFI.modulemap" \
#      "$SWIFT_BINDINGS_DIR/include/module.modulemap"

#   XCFRAMEWORK="$SWIFT_BINDINGS_DIR/speem.xcframework"
#   echo "   • xcodebuild -create-xcframework → $XCFRAMEWORK"
#   xcodebuild -create-xcframework \
#     -library "$DEV_LIB" -headers "$SWIFT_BINDINGS_DIR/include" \
#     -library "$SIM_LIB" -headers "$SWIFT_BINDINGS_DIR/include" \
#     -output "$XCFRAMEWORK"

#   echo "📦 Building & launching iOS app…"
#   SIM_NAME="iPhone 16"
#   if ! xcrun simctl list devices booted | grep -q Booted; then
#     open -a Simulator; sleep 1
#     xcrun simctl boot "$SIM_NAME"
#     xcrun simctl bootstatus "$SIM_NAME" --wait
#   fi
#   xcodebuild \
#     -project "$ROOT/ios/speem.xcodeproj" \
#     -scheme speem \
#     -sdk iphonesimulator \
#     -destination "platform=iOS Simulator,name=$SIM_NAME" \
#     -derivedDataPath "$ROOT/ios/build" build
#   xcrun simctl install booted "$ROOT/ios/build/Build/Products/Debug-iphonesimulator/speem.app"
#   xcrun simctl launch booted com.wassimans.speem
# }

case "$cmd" in
  bindings)   generate ;;
  # android) android_steps ;;
  # ios)    ios_steps ;;
  # all)    rust_steps && android_steps && ios_steps ;;
  *) echo "Usage: $0 [generate]" && exit 1 ;;
esac
