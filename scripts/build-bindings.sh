#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/polkabind-core"
OUT_DIR="$ROOT/bindings"

# Where our freshly built cdylib will live:
DYLIB="$ROOT/target/release/libpolkabind.dylib"
SO="$ROOT/target/release/libpolkabind.so"

# Pick the right host‐library for this platform:
if [[ -f "$DYLIB" ]]; then
  HOST_LIB="$DYLIB"
elif [[ -f "$SO" ]]; then
  HOST_LIB="$SO"
else
  echo "❌ could not find libpolkabind.{dylib,so} in target/release"
  exit 1
fi

KOTLIN_BINDINGS_DIR="$OUT_DIR/kotlin"
SWIFT_BINDINGS_DIR="$OUT_DIR/swift"

cmd=${1:-generate}
shift || true

generate() {
  echo "🧹 Cleaning old bindings…"
  rm -rf "$KOTLIN_BINDINGS_DIR" "$SWIFT_BINDINGS_DIR"
  mkdir -p "$KOTLIN_BINDINGS_DIR" "$SWIFT_BINDINGS_DIR"

  echo "🛠️  Building core crate…"
  cargo build --manifest-path "$CORE_DIR/Cargo.toml" --release

  echo "🔧 Generating Kotlin bindings…"
  target/release/uniffi-bindgen generate \
    --library "$HOST_LIB" \
    --language kotlin \
    --no-format \
    --out-dir "$KOTLIN_BINDINGS_DIR" \
    #"$CORE_DIR/src/lib.rs"

  echo "🍎 Generating Swift bindings…"
  target/release/uniffi-bindgen generate \
    --library "$HOST_LIB" \
    --language swift \
    --out-dir "$SWIFT_BINDINGS_DIR" \
    #"$CORE_DIR/src/lib.rs"

  # Tweak the Swift import for implementation-only
  SWIFT_FILE="$SWIFT_BINDINGS_DIR/polkabind.swift"
  if [[ -f "$SWIFT_FILE" ]]; then
    # 1) Prepend the @_implementationOnly import
    sed -i '' '1s%^%@_implementationOnly import PolkabindFFI\n%' "$SWIFT_FILE"
    # 2) Remove any stray `import PolkabindFFI`
    sed -i '' '/^import PolkabindFFI$/d' "$SWIFT_FILE"
  fi
}

case "$cmd" in
  generate)   generate ;;
  *) echo "Usage: $0 generate" && exit 1 ;;
esac
