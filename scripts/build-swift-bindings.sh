#!/usr/bin/env bash
set -euo pipefail

# ——— Paths ———
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDINGS="$ROOT/bindings/swift"
OUT_XC="$ROOT/out/PolkabindSwift"
OUT_PKG="$ROOT/out/polkabind-swift-pkg"
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
RUST_DYLIB="$ROOT/target/release/libpolkabind.dylib"

# ——— 1) Build host dylib ———
echo "🛠️  Building Rust dylib…"
cargo build --release --manifest-path "$ROOT/Cargo.toml"
[[ -f "$RUST_DYLIB" ]] || { echo "❌ missing $RUST_DYLIB"; exit 1; }

# ——— 2) Generate Swift glue ———
echo "🧹 Generating Swift bindings…"
rm -rf "$BINDINGS"
mkdir -p "$BINDINGS"
"$UNIFFI_BIN" generate \
  --library "$RUST_DYLIB" \
  --language swift \
  --out-dir "$BINDINGS"

GLUE="$BINDINGS/polkabind.swift"
[[ -f "$GLUE" ]] || { echo "❌ UniFFI didn’t emit polkabind.swift"; exit 1; }

# patch for implementation-only import
sed -i '' \
  's|^import Foundation|import Foundation\n@_implementationOnly import polkabindFFI|' \
  "$GLUE"

# ——— 3) Build iOS slices (arm64 only) ———
echo "🐝 Compiling iOS + Simulator arm64 slices…"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

# ——— 4) Create tiny .framework bundles ———
echo "📂 Assembling .framework bundles…"
rm -rf "$OUT_XC/tmp-fwks"
mkdir -p "$OUT_XC/tmp-fwks/device" "$OUT_XC/tmp-fwks/simulator"

for slice in device simulator; do
  if [[ $slice == device ]]; then
    SRC="$ROOT/target/aarch64-apple-ios/release/libpolkabind.dylib"
  else
    SRC="$ROOT/target/aarch64-apple-ios-sim/release/libpolkabind.dylib"
  fi

  FWK="$OUT_XC/tmp-fwks/$slice/polkabindFFI.framework"
  mkdir -p "$FWK"/{Headers,Modules}

  # copy in the minimal Info.plist
  cp "$ROOT/scripts/FrameworkInfo.plist" "$FWK/Info.plist"

  # rename the dylib to the framework’s binary name
  cp "$SRC" "$FWK/polkabindFFI"

  # Give Xcode the install-name
  install_name_tool -id "@rpath/polkabindFFI.framework/polkabindFFI" \
                  "$FWK/polkabindFFI"

  # copy UniFFI headers + modulemap
  cp "$BINDINGS/polkabindFFI.h"       "$FWK/Headers/"
  cp "$BINDINGS/polkabindFFI.modulemap" "$FWK/Modules/module.modulemap"

  # patch it to be a framework module
  sed -i '' 's/^module /framework module /' "$FWK/Modules/module.modulemap"
done

# ——— 5) Make the .xcframework ———
echo "📦 Creating polkabindFFI.xcframework…"
rm -rf "$OUT_XC/polkabindFFI.xcframework"
xcodebuild -create-xcframework \
  -framework "$OUT_XC/tmp-fwks/device/polkabindFFI.framework" \
  -framework "$OUT_XC/tmp-fwks/simulator/polkabindFFI.framework" \
  -output "$OUT_XC/polkabindFFI.xcframework"

# ——— 6) Drop in Swift glue & Package.swift ———
echo "✂️  Laying out SwiftPM package…"
mkdir -p "$OUT_XC/Sources/Polkabind"
cp "$GLUE" "$OUT_XC/Sources/Polkabind/"

cat > "$OUT_XC/Package.swift" <<'EOF'
// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "Polkabind",
  platforms: [.iOS(.v13)],
  products: [
    .library(name: "Polkabind", targets: ["Polkabind"]),
  ],
  targets: [
    .binaryTarget(name: "polkabindFFI", path: "polkabindFFI.xcframework"),
    .target(name: "Polkabind", dependencies: ["polkabindFFI"]),
  ]
)
EOF

# ——— 7) Validate with xcodebuild ———
echo "🔗 Validating integration…"
pushd "$OUT_XC" >/dev/null
xcodebuild clean build \
  -scheme Polkabind \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  BUILD_DIR="build"
popd >/dev/null

# ——— 8) Produce minimal package for release ———
echo "🚚 Bundling minimal Swift package…"
rm -rf "$OUT_PKG"
mkdir -p "$OUT_PKG/Sources/Polkabind"
cp "$ROOT/LICENSE"      "$OUT_PKG/"
cp "$ROOT/docs/readmes/swift/README.md"   "$OUT_PKG/"
cp "$OUT_XC/Package.swift"           "$OUT_PKG/"
cp -R "$OUT_XC/polkabindFFI.xcframework" "$OUT_PKG/"
cp "$GLUE"             "$OUT_PKG/Sources/Polkabind/"

echo "✅ Done!
 • XCFramework → $OUT_XC/polkabindFFI.xcframework
 • Swift Package → $OUT_PKG"
