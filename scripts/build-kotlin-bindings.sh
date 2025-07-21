#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# 0.  Environment – keep UniFFI metadata alive on Linux
##############################################################################
if [[ "$(uname)" != "Darwin" ]]; then
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic -C link-arg=-Wl,--no-gc-sections"
fi

##############################################################################
# 1.  Paths & constants
##############################################################################
ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." && pwd )"

BINDINGS="$ROOT/bindings/kotlin"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"

case "$(uname)" in Darwin) EXT=dylib ;; *) EXT=so ;; esac
HOST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"

ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

##############################################################################
# 2.  Helper – portable ELF stripper
##############################################################################
strip_elf () {
  local f=$1

  # Prefer llvm-strip from the NDK (works on macOS & Linux)
  if [[ -n "${ANDROID_NDK_HOME:-}" ]] && \
     tool=$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip) && \
     [[ -x $tool ]]; then
    "$tool" --strip-unneeded "$f"
    return
  fi

  # GNU strip on Linux
  if [[ "$(uname)" == "Linux" ]]; then
    strip --strip-unneeded "$f"
    return
  fi

  # Otherwise keep symbols (macOS without NDK strip)
  echo "⚠️  No ELF-capable strip found; keeping symbols in $(basename "$f")"
}

##############################################################################
# 3.  Build workspace – produces host-platform uniffi-bindgen
##############################################################################
echo "🔨 Building workspace (debug symbols still in)…"
cargo build --release --workspace
[[ -x "$UNIFFI_BIN" ]] || { echo "❌ uniffi-bindgen not found"; exit 1; }

##############################################################################
# 4.  Rebuild host dylib (ensures metadata is present)
##############################################################################
cargo build --release -p polkabind-core
[[ -f "$HOST_DYLIB" ]] || { echo "❌ host dylib missing"; exit 1; }

echo "UniFFI symbols present:"
if [[ "$(uname)" == "Darwin" ]]; then
  nm -gU "$HOST_DYLIB" | grep UNIFFI_META >/dev/null
else
  nm -D --defined-only "$HOST_DYLIB" | grep UNIFFI_META >/dev/null
fi || { echo "❌ UniFFI metadata was stripped"; exit 1; }

##############################################################################
# 5.  Generate Kotlin glue
##############################################################################
echo "🧹 Generating Kotlin bindings…"
rm -rf "$BINDINGS" && mkdir -p "$BINDINGS"

"$UNIFFI_BIN" generate \
  --config   "$ROOT/uniffi.toml" \
  --no-format \
  --library  "$HOST_DYLIB" \
  --language kotlin \
  --out-dir  "$BINDINGS"

GLUE_SRC="$(find "$BINDINGS" -type f -iname '*.kt' -print -quit)"

if [[ -z "$GLUE_SRC" ]]; then
  echo "❌ UniFFI emitted no .kt glue under $BINDINGS"
  exit 1
fi
echo "   • Kotlin glue → $(realpath --relative-to="$ROOT" "$GLUE_SRC")"

##############################################################################
# 6.  Cross-compile stripped .so files for every Android ABI
##############################################################################
echo "🛠️  Cross-compiling Android targets…"
for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac

  cargo ndk --target "$TARGET" --platform 21 build --release

  SO="$ROOT/target/${TARGET}/release/libpolkabind.so"
  [[ -f "$SO" ]] || { echo "❌ $SO missing"; exit 1; }

  strip_elf "$SO"
  echo "   • $(basename "$SO") ⇒ $(du -h "$SO" | cut -f1)"
done

##############################################################################
# 7.  Create minimal Android library module
##############################################################################
echo "📂 Creating Gradle module skeleton…"
MOD="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MOD"
mkdir -p "$MOD/src/main/java/dev/polkabind"

cp "$GLUE_SRC" "$MOD/src/main/java/dev/polkabind/"

for ABI in "${ABIS[@]}"; do
  mkdir -p "$MOD/src/main/jniLibs/$ABI"
  case "$ABI" in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  cp "$ROOT/target/${TARGET}/release/libpolkabind.so" \
     "$MOD/src/main/jniLibs/$ABI/"
done

# — settings.gradle.kts —
cat >"$MOD/settings.gradle.kts" <<'GSET'
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
GSET

# — build.gradle.kts —
cat >"$MOD/build.gradle.kts" <<'GBLD'
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
plugins { id("com.android.library"); kotlin("android"); id("maven-publish") }

dependencies {
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.6.4")
}

android {
    namespace = "dev.polkabind"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        ndk { abiFilters += listOf("arm64-v8a","armeabi-v7a","x86_64","x86") }
    }
    publishing { singleVariant("release") }
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

afterEvaluate {
    publishing.publications.create<MavenPublication>("release") {
        groupId    = "dev.polkabind"
        artifactId = "polkabind-android"
        version    = "1.0.0-SNAPSHOT"
        from(components["release"])
    }
}
tasks.withType<KotlinCompile> { kotlinOptions.jvmTarget = "1.8" }
GBLD

##############################################################################
# 8.  Build AAR
##############################################################################
echo "🔧 Building AAR…"
pushd "$MOD" >/dev/null
[[ -f gradlew ]] || gradle wrapper --gradle-version 8.6 --distribution-type all
./gradlew -q clean bundleReleaseAar
popd >/dev/null

##############################################################################
# 9.  Assemble distributable archive
##############################################################################
echo "🚚 Bundling distributable package…"
rm -rf "$OUT_PKG" && mkdir -p "$OUT_PKG"
cp "$ROOT/LICENSE" "$OUT_PKG/"
cp "$ROOT/docs/readmes/kotlin/README.md" "$OUT_PKG/"
cp -R "$MOD/build/outputs/aar" "$OUT_PKG/aar"
cp -R "$MOD/src/main/java/dev/polkabind" "$OUT_PKG/src"

echo "✅ Success – package ready at $OUT_PKG"
