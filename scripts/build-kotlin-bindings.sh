#!/usr/bin/env bash
set -euo pipefail

# ——— Paths ———
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDINGS="$ROOT/bindings/kotlin"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"

# Pick the correct extension for the host dylib
case "$(uname)" in
  Darwin) EXT=dylib ;;
  *)      EXT=so ;;
esac
RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

# Android ABIs to target
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

cd "$ROOT"

# ————————————————————————————————————————————————————————————
# ❶  Build *everything* once so the right uniffi-bindgen is present
echo "🔨 Building host tools (workspace)…"
if [[ "$(uname)" != "Darwin" ]]; then
  # Linux needs both flags to keep the metadata alive
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic -C link-arg=-Wl,--no-gc-sections"
fi
cargo build --release --workspace
unset RUSTFLAGS

UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
[[ -x "$UNIFFI_BIN" ]] || { echo "❌ missing bindgen tool $UNIFFI_BIN"; exit 1; }

# ❷  Re-build only the host cdylib with the same linker flags
if [[ "$(uname)" != "Darwin" ]]; then
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic -C link-arg=-Wl,--no-gc-sections"
fi
cargo build --release -p polkabind-core
unset RUSTFLAGS
[[ -f "$RUST_DYLIB" ]] || { echo "❌ missing host library $RUST_DYLIB"; exit 1; }

# ---------- quick symbol dump *before* generating ----------
echo -e "\n— nm -D | head —\n" > /tmp/uniffi.dylib.nm
nm -D --defined-only "$RUST_DYLIB" | head -n 40 >> /tmp/uniffi.dylib.nm 2>&1

echo -e "\n— ldd uniffi-bindgen —"
ldd "$UNIFFI_BIN" || true            # don’t abort even if it fails

echo -e "\n— ldd libpolkabind.so —"
ldd "$RUST_DYLIB"    || true

# ————————————————————————————————————————————————————————————
# ❸  Generate Kotlin glue
echo "🧹 Generating Kotlin bindings…"
rm -rf "$BINDINGS"
mkdir -p "$BINDINGS"

# Helper that tries catchsegv; if that prints nothing fall back to strace
run_bindgen() {
  echo "❯ catchsegv $*"
  if catchsegv "$@"; then
    return 0
  fi

  echo -e "\n⚠️  catchsegv printed nothing, retrying under strace…"
  strace -f -o /tmp/uniffi.strace "$@"
}

set -o pipefail
run_bindgen \
  "$UNIFFI_BIN" generate \
    --config   "$ROOT/uniffi.toml" \
    --no-format \
    --library  "$RUST_DYLIB" \
    --language kotlin \
    --out-dir  "$BINDINGS" 2>&1 | tee /tmp/uniffi.log

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
if [[ ! -f "$GLUE_SRC" ]]; then
  echo "❌ UniFFI didn’t emit polkabind.kt"
  echo "ℹ️  Saved logs:"
  echo "   • /tmp/uniffi.log      (stdout/stderr)"
  [ -f /tmp/uniffi.strace ] && echo "   • /tmp/uniffi.strace   (syscall trace)"
  exit 1
fi

# ————————————————————————————————————————————————————————————
# ❹  Cross-compile Rust for Android ABIs
echo "🛠️  Cross-compiling Rust for Android ABIs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac

  cargo ndk --target "$TARGET" --platform 21 build --release
  [[ -f "$ROOT/target/${TARGET}/release/libpolkabind.so" ]] \
    || { echo "❌ missing libpolkabind.so for $TARGET"; exit 1; }
done

# ————————————————————————————————————————————————————————————
# ❺  Lay out Android library module skeleton
echo "📂 Setting up Android library module…"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind"

for ABI in "${ABIS[@]}"; do
  mkdir -p "$MODULE_DIR/src/main/jniLibs/$ABI"
done

cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

echo "📂 Copying .so into jniLibs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  cp "$ROOT/target/${TARGET}/release/libpolkabind.so" \
     "$MODULE_DIR/src/main/jniLibs/$ABI/"
done

# ————————————————————————————————————————————————————————————
# ❻  Generate minimal Gradle files
cat > "$MODULE_DIR/settings.gradle.kts" <<'EOF'
pluginManagement {
    repositories {
        google(); mavenCentral(); gradlePluginPortal()
    }
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

cat > "$MODULE_DIR/build.gradle.kts" <<'EOF'
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
    publishing {
        publications {
            create<MavenPublication>("release") {
                groupId = "dev.polkabind"
                artifactId = "polkabind-android"
                version = "1.0.0-SNAPSHOT"
                from(components["release"])
            }
        }
        repositories { maven { url = uri("$rootDir/../../PolkabindKotlin/maven-snapshots") } }
    }
}
tasks.withType<KotlinCompile> { kotlinOptions.jvmTarget = "1.8" }
EOF

# ————————————————————————————————————————————————————————————
# ❼  Build the AAR
echo "🔧 Bootstrapping Gradle wrapper & building AAR…"
pushd "$MODULE_DIR" >/dev/null
[[ -f gradlew ]] || gradle wrapper --gradle-version 8.6 --distribution-type all
./gradlew -q clean bundleReleaseAar publishToMavenLocal
popd >/dev/null

# ————————————————————————————————————————————————————————————
# ❽  Assemble distributable package
echo "🚚 Bundling Kotlin package…"
rm -rf "$OUT_PKG"
mkdir -p "$OUT_PKG"
cp "$ROOT/LICENSE" "$OUT_PKG/"
cp "$ROOT/docs/readmes/kotlin/README.md" "$OUT_PKG/"
cp -R "$MODULE_DIR/build/outputs/aar" "$OUT_PKG/aar"
cp -R "$MODULE_DIR/src/main/java/dev/polkabind" "$OUT_PKG/src"

echo "✅ Done!
 • AAR snapshot → $MODULE_DIR/build/outputs/aar
 • Kotlin package → $OUT_PKG"
