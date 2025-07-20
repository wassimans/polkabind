#!/usr/bin/env bash
set -euo pipefail

# ——— Paths ———
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDINGS="$ROOT/bindings/kotlin"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"

# Pick the correct extension for our platform
case "$(uname)" in
  Darwin) EXT=dylib ;;
  *)      EXT=so    ;;
esac
RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

# Android ABIs we target
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

cd "$ROOT"

echo "🛠️  Cross-compiling Rust for Android ABIs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac

  echo "  • Building for $TARGET"
  cargo ndk --target "$TARGET" --platform 21 build --release
  if [[ ! -f "$ROOT/target/$TARGET/release/libpolkabind.so" ]]; then
    echo "❌ missing libpolkabind.so for $TARGET"
    exit 1
  fi
done

echo "🔨 Building the uniffi-bindgen tool…"
cargo build --release -p polkabind-bindgen
echo "🛠️  Building Rust host library…"
cargo build --release --manifest-path "$ROOT/Cargo.toml"

echo "→ Checking for host dylib and bindgen binary:"
[[ -f "$RUST_DYLIB" ]]   && echo "✅ Found host .so: $RUST_DYLIB" \
                       || { echo "❌ missing $RUST_DYLIB"; exit 1; }
[[ -x "$UNIFFI_BIN" ]]    && echo "✅ Found uniffi-bindgen: $UNIFFI_BIN" \
                       || { echo "❌ missing $UNIFFI_BIN"; exit 1; }

echo "📋 Contents of uniffi.toml:"
sed -n '1,20p' "$ROOT/uniffi.toml"

echo "🔍 Dumping first 30 lines of dynamic symbols in $RUST_DYLIB:"
if command -v nm &>/dev/null; then
  nm -D "$RUST_DYLIB" | head -n 30 || true
else
  objdump -T "$RUST_DYLIB" | head -n 30 || true
fi

echo "🔍 Looking for UniFFI metadata section headers in $RUST_DYLIB:"
if command -v readelf &>/dev/null; then
  readelf -S "$RUST_DYLIB" | grep -i uniffi || echo "(none found)"
else
  echo "⚠️  readelf not available"
fi

echo "🧹 Generating Kotlin bindings (verbose)…"
rm -rf "$BINDINGS"
mkdir -p "$BINDINGS"

echo "→ Command:"
echo "  $UNIFFI_BIN generate \\"
echo "    --config \"$ROOT/uniffi.toml\" \\"
echo "    --no-format \\"
echo "    --library \"$RUST_DYLIB\" \\"
echo "    --language kotlin \\"
echo "    --verbose \\"
echo "    --out-dir \"$BINDINGS\""

# if --verbose isn’t supported, it will just warn us
"$UNIFFI_BIN" generate \
  --config "$ROOT/uniffi.toml" \
  --no-format \
  --library "$RUST_DYLIB" \
  --language kotlin \
  --verbose \
  --out-dir "$BINDINGS" || true

echo "👀 Now listing $BINDINGS:"
find "$BINDINGS" -type f | sed 's/^/   • /'

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
if [[ ! -f "$GLUE_SRC" ]]; then
  echo "❌ UniFFI didn’t emit polkabind.kt"
  exit 1
else
  echo "✅ Found generated Kotlin glue at $GLUE_SRC"
fi

# …then continue with steps 3-7 as before…
echo "📂 (rest of the script would lay out the Android module, etc.)"

# ——— 5) Lay out Android library module ———
echo "📂 Setting up Android library module at $OUT_LIBMODULE"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR" && echo "   Cleared old module"
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind" \
         "$MODULE_DIR/src/main/jniLibs" && echo "   Created module dirs"

echo "   Copying generated kotlin file to module"
cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# copy .so into jniLibs
echo "📂 Copying Android .so into jniLibs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  SRC="$ROOT/target/${TARGET}/release/libpolkabind.so"
  DST="$MODULE_DIR/src/main/jniLibs/$ABI/libpolkabind.so"
  echo "   Copying $SRC → $DST"
  mkdir -p "$(dirname "$DST")"
  cp "$SRC" "$DST"
done

echo "✅ All steps completed successfully up to binding generation."

# ——— 5) Lay out Android library module ———
echo "📂 Setting up Android library module at $OUT_LIBMODULE"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR" && echo "   Cleared old module"
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind" \
         "$MODULE_DIR/src/main/jniLibs" && echo "   Created module dirs"

echo "   Copying generated kotlin file to module"
cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# copy .so into jniLibs
echo "📂 Copying Android .so into jniLibs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  SRC="$ROOT/target/${TARGET}/release/libpolkabind.so"
  DST="$MODULE_DIR/src/main/jniLibs/$ABI/libpolkabind.so"
  echo "   Copying $SRC → $DST"
  mkdir -p "$(dirname "$DST")"
  cp "$SRC" "$DST"
done

echo "✅ All steps completed successfully up to binding generation."
