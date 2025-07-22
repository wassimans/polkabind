#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# 0.  Paths
##############################################################################
ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." && pwd )"

BINDINGS="$ROOT/bindings/swift"
OUT_XC="$ROOT/out/PolkabindSwift"
OUT_PKG="$ROOT/out/polkabind-swift-pkg"

UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
HOST_DYLIB="$ROOT/target/release/libpolkabind.dylib"

##############################################################################
# 1.  Build host Polkabind bindgen and dylib binaries
##############################################################################
echo "🛠️  Building Rust dylib (host)…"
cargo build --release --manifest-path "$ROOT/Cargo.toml"
[[ -f "$HOST_DYLIB" ]] || { echo "❌ missing $HOST_DYLIB"; exit 1; }

##############################################################################
# 2.  Generate Swift glue
##############################################################################
echo "🧹 Generating Swift bindings…"
rm -rf "$BINDINGS" && mkdir -p "$BINDINGS"

"$UNIFFI_BIN" generate \
  --library  "$HOST_DYLIB" \
  --language swift \
  --out-dir  "$BINDINGS"

GLUE="$BINDINGS/polkabind.swift"
[[ -f "$GLUE" ]] || { echo "❌ UniFFI didn’t emit polkabind.swift"; exit 1; }

# Implementation-only import to silence Xcode warnings
sed -i '' \
  's|^import Foundation|import Foundation\n@_implementationOnly import polkabindFFI|' \
  "$GLUE"

##############################################################################
# 3.  Build iOS slices (device arm64 & sim arm64)
##############################################################################
echo "🐝 Compiling iOS + Simulator arm64 slices…"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

##############################################################################
# 4.  Create minimal .framework bundles
##############################################################################
echo "📂 Assembling .framework bundles…"
rm -rf "$OUT_XC/tmp-fwks"
mkdir -p "$OUT_XC/tmp-fwks/device" "$OUT_XC/tmp-fwks/simulator"

strip_macho () {
  # strip -x → remove local/global-unexported symbols (Mach-O only)
  /usr/bin/strip -x "$1"
}

for slice in device simulator; do
  if [[ $slice == device ]]; then
    SRC="$ROOT/target/aarch64-apple-ios/release/libpolkabind.dylib"
  else
    SRC="$ROOT/target/aarch64-apple-ios-sim/release/libpolkabind.dylib"
  fi

  FWK="$OUT_XC/tmp-fwks/$slice/polkabindFFI.framework"
  mkdir -p "$FWK"/{Headers,Modules}

  # 4-a  copy template Info.plist
  cp "$ROOT/scripts/FrameworkInfo.plist" "$FWK/Info.plist"

  # 4-b  rename + copy dylib
  cp "$SRC" "$FWK/polkabindFFI"
  strip_macho "$FWK/polkabindFFI"

  # 4-c  fix install-name
  install_name_tool -id "@rpath/polkabindFFI.framework/polkabindFFI" \
                    "$FWK/polkabindFFI"

  # 4-d  headers + modulemap
  cp "$BINDINGS/polkabindFFI.h"         "$FWK/Headers/"
  cp "$BINDINGS/polkabindFFI.modulemap" "$FWK/Modules/module.modulemap"
  sed -i '' 's/^module /framework module /' "$FWK/Modules/module.modulemap"

  echo "   • $(basename "$FWK") dylib ⇒ $(du -h "$FWK/polkabindFFI" | cut -f1)"
done

##############################################################################
# 5.  Create XCFramework
##############################################################################
echo "📦 Creating polkabindFFI.xcframework…"
rm -rf "$OUT_XC/polkabindFFI.xcframework"
xcodebuild -create-xcframework \
  -framework "$OUT_XC/tmp-fwks/device/polkabindFFI.framework" \
  -framework "$OUT_XC/tmp-fwks/simulator/polkabindFFI.framework" \
  -output   "$OUT_XC/polkabindFFI.xcframework"

##############################################################################
# 6.  SwiftPM layout
##############################################################################
echo "✂️  Laying out Swift Package…"
mkdir -p "$OUT_XC/Sources/Polkabind"
cp "$GLUE" "$OUT_XC/Sources/Polkabind/"

cat > "$OUT_XC/Package.swift" <<'SPM'
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
SPM

##############################################################################
# 7.  Sanity-check build
##############################################################################
echo "🔗 Validating with xcodebuild…"
pushd "$OUT_XC" >/dev/null
xcodebuild -quiet clean build \
  -scheme Polkabind \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  BUILD_DIR="build"
popd >/dev/null

##############################################################################
# 8.  Produce trimmed release package
##############################################################################
echo "🚚 Bundling minimal Swift package…"
rm -rf "$OUT_PKG"
mkdir -p "$OUT_PKG/Sources/Polkabind"

cp "$ROOT/LICENSE"                       "$OUT_PKG/"
cp "$ROOT/docs/readmes/swift/README.md"  "$OUT_PKG/"
cp "$OUT_XC/Package.swift"               "$OUT_PKG/"
cp -R "$OUT_XC/polkabindFFI.xcframework" "$OUT_PKG/"
cp "$GLUE"                               "$OUT_PKG/Sources/Polkabind/"

echo "✅ Done!
 • XCFramework → $OUT_XC/polkabindFFI.xcframework
 • Swift Package → $OUT_PKG"
