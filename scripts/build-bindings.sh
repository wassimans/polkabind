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

case "$cmd" in
  bindings)   generate ;;
  *) echo "Usage: $0 [generate]" && exit 1 ;;
esac
