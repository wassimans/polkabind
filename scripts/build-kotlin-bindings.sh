#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# 0. Global build flags
###############################################################################
# Linux needs the metadata kept alive **and** exported from the shared library.
if [[ "$(uname)" != "Darwin" ]]; then
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic -C link-arg=-Wl,--no-gc-sections"
fi
# Prevent Cargo’s `[profile.release] strip = true` from removing the symbols
export CARGO_PROFILE_RELEASE_STRIP=none

###############################################################################
# 1. Paths & helpers
###############################################################################
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDINGS="$ROOT/bindings/kotlin"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"

case "$(uname)" in
  Darwin) EXT=dylib;  NM="nm -gU" ;;  # Mach-O
  *)      EXT=so;     NM="nm -D --defined-only" ;;  # ELF
esac
RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

###############################################################################
# 1.½  (NEW) portable ELF-stripper for the Android .so’s
###############################################################################
strip_elf() {
  local f=$1
  # Prefer llvm-strip from the NDK (works on macOS & Linux)
  if [[ -n "${ANDROID_NDK_HOME:-}" ]] && \
     tool=$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip) && \
     [[ -x $tool ]]; then
    "$tool" --strip-unneeded "$f"
    return
  fi
  # GNU strip on Linux hosts
  if [[ "$(uname)" == "Linux" ]]; then
    strip --strip-unneeded "$f"
    return
  fi
  # Otherwise: keep symbols (macOS without NDK llvm-strip)
  echo "⚠️  cannot strip $(basename "$f") – keeping symbols"
}

###############################################################################
# 2. Build the entire workspace once
###############################################################################
echo "🔨 Building workspace (host tools + dylib)…"
cargo build --release --workspace

UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
[[ -x "$UNIFFI_BIN" ]] || { echo "❌ uniffi-bindgen missing"; exit 1; }

echo "bindgen version     : $("$UNIFFI_BIN" --version)"
echo "host dylib produced : $RUST_DYLIB"

# Quick sanity-check that metadata is present
echo -e "\nUniFFI symbols in host dylib:"
if ! $NM "$RUST_DYLIB" | grep -q UNIFFI_META_NAMESPACE_; then
  echo "❌ UniFFI metadata NOT found; the dylib would be stripped."
  exit 1
fi
$NM "$RUST_DYLIB" | grep UNIFFI_META | head

###############################################################################
# 3. Generate Kotlin bindings
###############################################################################
echo -e "\n🧹 Generating Kotlin bindings…"
rm -rf "$BINDINGS" && mkdir -p "$BINDINGS"

"$UNIFFI_BIN" generate \
  --config   "$ROOT/uniffi.toml" \
  --no-format \
  --library  "$RUST_DYLIB" \
  --language kotlin \
  --out-dir  "$BINDINGS"

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
[[ -f "$GLUE_SRC" ]] || { echo "❌ polkabind.kt absent"; exit 1; }

###############################################################################
# 4. Cross-compile Rust for the Android ABIs   (now stripped afterwards)
###############################################################################
ABIS=(arm64-v8a armeabi-v7a)
echo -e "\n🛠️  Building Android .so files…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
  esac

  cargo ndk --target "$TARGET" --platform 21 build --release
  SO="$ROOT/target/${TARGET}/release/libpolkabind.so"
  [[ -f "$SO" ]] || { echo "❌ .so for $TARGET missing"; exit 1; }

  # ──► optimisation bit
  strip_elf "$SO"
  echo "   • $(basename "$SO") size ⇒ $(du -h "$SO" | cut -f1)"
done

###############################################################################
# 5. Lay out a minimal Android library module
###############################################################################
echo -e "\n📂 Preparing Android library module…"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind"

# -- glue
cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# -- jniLibs
for ABI in "${ABIS[@]}"; do
  mkdir -p "$MODULE_DIR/src/main/jniLibs/$ABI"
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
  esac
  cp "$ROOT/target/${TARGET}/release/libpolkabind.so" \
     "$MODULE_DIR/src/main/jniLibs/$ABI/"
done

# -- Gradle files
cat >"$MODULE_DIR/settings.gradle.kts" <<'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
    plugins {
        id("com.android.library") version "8.4.0"
        kotlin("android")         version "1.9.20"
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "polkabind-android"
EOF

cat >"$MODULE_DIR/build.gradle.kts" <<'EOF'
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.library")
    kotlin("android")
}

dependencies {
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.6.4")
}

android {
    namespace  = "dev.polkabind"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        ndk { abiFilters += listOf("arm64-v8a","armeabi-v7a") }
    }
    publishing { singleVariant("release") }
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

tasks.withType<KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "1.8"
}
EOF

###############################################################################
# 6. Build the AAR
###############################################################################
echo -e "\n🔧 Building AAR…"
pushd "$MODULE_DIR" >/dev/null
[[ -f gradlew ]] || gradle wrapper --gradle-version 8.6 --distribution-type all
./gradlew -q clean bundleReleaseAar
popd >/dev/null

###############################################################################
# 7. Assemble distributable package
###############################################################################
echo -e "\n🚚 Bundling Kotlin package…"
rm -rf "$OUT_PKG" && mkdir -p "$OUT_PKG"
cp "$ROOT/LICENSE" "$OUT_PKG/"
cp "$ROOT/docs/readmes/kotlin/README.md" "$OUT_PKG/"
cp -R "$MODULE_DIR/build/outputs/aar" "$OUT_PKG/aar"
cp -R "$MODULE_DIR/src/main/java/dev/polkabind" "$OUT_PKG/src"


###############################################################################
# 8. Inject minimal Gradle project for JitPack / maven-publish
###############################################################################
echo -e "\n🛠️  Adding tiny Gradle project for JitPack…"
cat >"$OUT_PKG/settings.gradle.kts" <<'EOF'
rootProject.name = "polkabind-kotlin-pkg"
EOF

cat >"$OUT_PKG/build.gradle.kts" <<'EOF'
plugins {
  `maven-publish`
  `java-library`
}

group = "com.github.Polkabind"
// version is picked up from the Git tag by JitPack

publishing {
  publications {
    create<MavenPublication>("aar") {
      artifactId = "polkabind-kotlin-pkg"
      // point at the prebuilt AAR in this zip
      artifact("$projectDir/aar/polkabind-android-release.aar")
    }
  }
}
EOF

echo -e "\n✅ Success – Kotlin package ready at $OUT_PKG"
