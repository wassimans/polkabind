# #!/usr/bin/env bash
# set -euo pipefail

# # ——— Paths ———
# ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# BINDINGS="$ROOT/bindings/kotlin"
# OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
# OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"
# UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
# # Pick the correct extension for our platform
# case "$(uname)" in
#   Darwin) EXT=dylib ;;
#   *)      EXT=so    ;;
# esac
# # Use the host dynamic library (uniffi only needs the metadata)
# RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

# # Android ABIs we target
# ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

# cd "$ROOT"

# # ——— 1) Cross-compile Rust for Android ABIs ———
# echo "🛠️  Cross-compiling Rust for Android ABIs…"
# for ABI in "${ABIS[@]}"; do
#   case $ABI in
#     arm64-v8a)   TARGET=aarch64-linux-android ;;
#     armeabi-v7a) TARGET=armv7-linux-androideabi ;;
#     x86_64)      TARGET=x86_64-linux-android ;;
#     x86)         TARGET=i686-linux-android ;;
#   esac

#   cargo ndk --target "$TARGET" --platform 21 build --release
#   if [[ ! -f "$ROOT/target/${TARGET}/release/libpolkabind.so" ]]; then
#     echo "❌ missing libpolkabind.so for $TARGET"
#     exit 1
#   fi
# done

# echo "🔨 Building the uniffi-bindgen tool…"
# cargo build --release -p polkabind-bindgen

# # Build host library & bindgen tool
# echo "🛠️  Building Rust host library & bindgen…"
# cargo build --release --manifest-path "$ROOT/Cargo.toml"
# [[ -f "$RUST_DYLIB" ]] || { echo "❌ missing $RUST_DYLIB"; exit 1; }
# [[ -f "$UNIFFI_BIN" ]]  || { echo "❌ missing $UNIFFI_BIN";  exit 1; }

# # ——— 2) Generate Kotlin glue ———
# echo "🧹 Generating Kotlin bindings…"
# rm -rf "$BINDINGS"
# mkdir -p "$BINDINGS"
# "$UNIFFI_BIN" generate \
#   --config "$ROOT/uniffi.toml" \
#   --no-format \
#   --library "$RUST_DYLIB" \
#   --language kotlin \
#   --out-dir "$BINDINGS"

# GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
# if [[ ! -f "$GLUE_SRC" ]]; then
#   echo "❌ UniFFI didn’t emit polkabind.kt"
#   exit 1
# fi

# # ——— 3) Lay out Android library module ———
# echo "📂 Setting up Android library module…"
# MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
# rm -rf "$MODULE_DIR"

# # sources & jniLibs dirs
# mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind"
# for ABI in "${ABIS[@]}"; do
#   mkdir -p "$MODULE_DIR/src/main/jniLibs/$ABI"
# done

# # copy glue
# cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# # copy .so into jniLibs
# echo "📂 Copying .so into jniLibs…"
# for ABI in "${ABIS[@]}"; do
#   case $ABI in
#     arm64-v8a)   TARGET=aarch64-linux-android ;;
#     armeabi-v7a) TARGET=armv7-linux-androideabi ;;
#     x86_64)      TARGET=x86_64-linux-android ;;
#     x86)         TARGET=i686-linux-android ;;
#   esac

#   SRC="$ROOT/target/${TARGET}/release/libpolkabind.so"
#   DST="$MODULE_DIR/src/main/jniLibs/$ABI/libpolkabind.so"
#   cp "$SRC" "$DST"
# done

# # ——— 4) Create settings.gradle.kts w/ pluginManagement ———
# cat > "$MODULE_DIR/settings.gradle.kts" <<'EOF'
# pluginManagement {
#     repositories {
#         google()
#         mavenCentral()
#         gradlePluginPortal()
#     }
#     plugins {
#         id("com.android.library") version "8.4.0"
#         kotlin("android")          version "1.9.20"
#     }
# }

# dependencyResolutionManagement {
#     repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
#     repositories {
#         google()
#         mavenCentral()
#     }
# }
# rootProject.name = "polkabind-android"
# EOF

# # ——— 5) Create build.gradle.kts ———
# cat > "$MODULE_DIR/build.gradle.kts" <<'EOF'
# import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
# plugins {
#     id("com.android.library")
#     kotlin("android")
#     id("maven-publish")
# }

# dependencies {
#     // UniFFI needs JNA for the JNI bridge
#     implementation("net.java.dev.jna:jna:5.13.0@aar")
#     // UniFFI uses kotlinx-coroutines for async APIs
#     implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.6.4")
# }

# android {
#     namespace = "dev.polkabind"
#     compileSdk = 35

#     defaultConfig {
#         minSdk    = 24
#         // targetSdkVersion(34)
#         ndk {
#             abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
#         }
#     }

#     publishing {
#         // only publish the release build variant
#         singleVariant("release")
#     }

#     sourceSets["main"].apply {
#         jniLibs.srcDirs("src/main/jniLibs")
#     }
# }

# afterEvaluate {
#   publishing {
#     publications {
#       create<MavenPublication>("release") {
#         groupId    = "dev.polkabind"
#         artifactId = "polkabind-android"
#         version    = "1.0.0-SNAPSHOT"

#         from(components["release"])
#       }
#     }
#     repositories {
#       maven { url = uri("$rootDir/../../PolkabindKotlin/maven-snapshots") }
#     }
#   }
# }
# tasks.withType<KotlinCompile> {
#     kotlinOptions.jvmTarget = "1.8"
# }
# EOF

# # ——— 6) Bootstrap Gradle wrapper & build AAR ———
# echo "🔧 Bootstrapping Gradle wrapper (8.6) & building AAR…"
# pushd "$MODULE_DIR" >/dev/null

# if [[ ! -f gradlew ]]; then
#   gradle wrapper --gradle-version 8.6 --distribution-type all
# fi
# ./gradlew clean bundleReleaseAar publishToMavenLocal
# popd >/dev/null

# # ——— 7) Package minimal Kotlin artifact ———
# echo "🚚 Bundling Kotlin package…"
# rm -rf "$OUT_PKG"
# mkdir -p "$OUT_PKG"

# cp "$ROOT/LICENSE" "$OUT_PKG/"
# cp "$ROOT/docs/readmes/kotlin/README.md" "$OUT_PKG/"
# cp -R "$MODULE_DIR/build/outputs/aar" "$OUT_PKG/aar"
# cp -R "$MODULE_DIR/src/main/java/dev/polkabind" "$OUT_PKG/src"

# echo "✅ Done!
#  • AAR snapshot → $MODULE_DIR/build/outputs/aar
#  • Kotlin package → $OUT_PKG"


#!/usr/bin/env bash
set -euo pipefail

# ——— Paths ———
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "🔍 ROOT is $ROOT"
BINDINGS="$ROOT/bindings/kotlin"
echo "🔍 BINDINGS dir will be $BINDINGS"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
echo "🔍 OUT_LIBMODULE is $OUT_LIBMODULE"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"
echo "🔍 OUT_PKG is $OUT_PKG"
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
echo "🔍 UNIFFI_BIN expected at $UNIFFI_BIN"

# Pick the correct extension for our host platform
UNAME="$(uname)"
echo "🔍 Host uname: $UNAME"
case "$UNAME" in
  Darwin) EXT=dylib ;;
  *)      EXT=so    ;;
esac
echo "🔍 Using extension: .$EXT"

RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"
echo "🔍 RUST_DYLIB expected at $RUST_DYLIB"

# Android ABIs we target
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)
echo "🔍 Target ABIs: ${ABIS[*]}"

cd "$ROOT"
echo "📁 cd to $ROOT"

# ——— 1) Cross-compile Rust for Android ABIs ———
echo "🛠️  Cross-compiling Rust for Android ABIs…"
for ABI in "${ABIS[@]}"; do
  echo "   ▶️ Building for $ABI"
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  echo "     → cargo ndk --target $TARGET --platform 21 build --release"
  cargo ndk --target "$TARGET" --platform 21 build --release
  echo "     → checking $ROOT/target/${TARGET}/release/libpolkabind.so"
  if [[ ! -f "$ROOT/target/${TARGET}/release/libpolkabind.so" ]]; then
    echo "❌ missing libpolkabind.so for $TARGET at $ROOT/target/${TARGET}/release/libpolkabind.so"
    ls -l "$ROOT/target/${TARGET}/release"
    exit 1
  fi
done

# ——— 1.5) Build the bindgen tool itself ———
echo "🔨 Building the uniffi-bindgen tool (polkabind-bindgen)…"
cargo build --release -p polkabind-bindgen
echo "   → cargo build exit code $?"

echo "   Checking for bindgen binary:"
if [[ -x "$UNIFFI_BIN" ]]; then
  echo "✅ Found uniffi-bindgen: $(ls -lh "$UNIFFI_BIN")"
  echo "   Version dump:"
  "$UNIFFI_BIN" --version || echo "   (version flag unsupported)"
else
  echo "❌ Missing or non-executable $UNIFFI_BIN"
  ls -l "$(dirname "$UNIFFI_BIN")"
  exit 1
fi

# ——— 2) Build host library ———
echo "🛠️  Building Rust host library…"
cargo build --release --manifest-path "$ROOT/Cargo.toml"
echo "   → build exit code $?"
echo "   Checking for $RUST_DYLIB"
if [[ -f "$RUST_DYLIB" ]]; then
  echo "✅ Found host dylib: $(ls -lh "$RUST_DYLIB")"
else
  echo "❌ Missing $RUST_DYLIB"
  ls -l "$(dirname "$RUST_DYLIB")"
  exit 1
fi

# ——— 3) Dump uniffi.toml for sanity ———
echo "📋 Contents of uniffi.toml:"
sed -n '1,200p' "$ROOT/uniffi.toml" || echo "(could not read uniffi.toml)"

# ——— 4) Generate Kotlin glue ———
echo "🧹 Generating Kotlin bindings…"
echo "   Removing old bindings at $BINDINGS"
rm -rf "$BINDINGS"
echo "   Creating $BINDINGS"
mkdir -p "$BINDINGS"
echo "   Invoking bindgen:"
echo "   $UNIFFI_BIN generate --config \"$ROOT/uniffi.toml\" --no-format --library \"$RUST_DYLIB\" --language kotlin --out-dir \"$BINDINGS\""
"$UNIFFI_BIN" generate \
  --config "$ROOT/uniffi.toml" \
  --no-format \
  --library "$RUST_DYLIB" \
  --language kotlin \
  --out-dir "$BINDINGS" 2>&1 | sed 's/^/     | /'

echo "   Listing $BINDINGS tree:"
find "$BINDINGS" -maxdepth 3 | sed 's/^/     | /'

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
echo "   Expecting generated file at $GLUE_SRC"
if [[ ! -f "$GLUE_SRC" ]]; then
  echo "❌ UniFFI didn’t emit polkabind.kt"
  echo "   Contents of $BINDINGS:"
  ls -R "$BINDINGS"
  exit 1
else
  echo "✅ Found binding: $(ls -lh "$GLUE_SRC")"
fi

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
