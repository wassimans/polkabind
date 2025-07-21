#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------
# Export once, leave it in scope for every subsequent `cargo build`.
# (The extra --no-gc-sections keeps the metadata from being stripped.)
if [[ "$(uname)" != "Darwin" ]]; then
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic -C link-arg=-Wl,--no-gc-sections"
fi
# ---------------------------------------------------------------------

# ——— Paths ———
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDINGS="$ROOT/bindings/kotlin"
OUT_LIBMODULE="$ROOT/out/PolkabindKotlin"
OUT_PKG="$ROOT/out/polkabind-kotlin-pkg"

# correct dylib/so suffix
case "$(uname)" in
  Darwin) EXT=dylib ;; *) EXT=so ;;
esac
RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

# ---------------------------------------------------------------------
# 1. Build the whole workspace once (this gives us a *Linux* uniffi-bindgen)
# ---------------------------------------------------------------------
echo "🔨 Building workspace…"
cargo build --release --workspace
UNIFFI_BIN="$ROOT/target/release/uniffi-bindgen"
[[ -x "$UNIFFI_BIN" ]] || { echo "bindgen missing"; exit 1; }

# ---------------------------------------------------------------------
# 2. Re-build the host cdylib (polkabind-core) – metadata now exported
# ---------------------------------------------------------------------
cargo build --release -p polkabind-core
[[ -f "$RUST_DYLIB" ]] || { echo "host dylib missing"; exit 1; }

# quick sanity check
echo "UniFFI symbols in $RUST_DYLIB:"
nm -D --defined-only "$RUST_DYLIB" | grep UNIFFI_META || {
  echo "❌ metadata still missing"; exit 1; }

# ---------------------------------------------------------------------
# 3. Generate Kotlin bindings
# ---------------------------------------------------------------------
echo "🧹 Generating Kotlin bindings…"
rm -rf "$BINDINGS" && mkdir -p "$BINDINGS"
"$UNIFFI_BIN" generate \
  --config   "$ROOT/uniffi.toml" \
  --no-format \
  --library  "$RUST_DYLIB" \
  --language kotlin \
  --out-dir  "$BINDINGS"

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
[[ -f "$GLUE_SRC" ]] || { echo "❌ polkabind.kt absent"; exit 1; }

# ---------------------------------------------------------------------
# 4. Cross-compile for Android ABIs
# ---------------------------------------------------------------------
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)
echo "🛠️  Building Android .so files…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  cargo ndk --target "$TARGET" --platform 21 build --release
  [[ -f "$ROOT/target/${TARGET}/release/libpolkabind.so" ]] \
    || { echo "❌ .so for $TARGET missing"; exit 1; }
done

# ---------------------------------------------------------------------
# 5. Minimal Android library module + Gradle wrapper
# ---------------------------------------------------------------------
echo "📂 Preparing Android library module…"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR"
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind"

# copy glue
cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# jniLibs
for ABI in "${ABIS[@]}"; do
  mkdir -p "$MODULE_DIR/src/main/jniLibs/$ABI"
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  cp "$ROOT/target/${TARGET}/release/libpolkabind.so" \
     "$MODULE_DIR/src/main/jniLibs/$ABI/"
done

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
plugins { id("com.android.library"); kotlin("android"); id("maven-publish") }
dependencies {
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.6.4")
}
android {
    namespace = "dev.polkabind"
    compileSdk = 35
    defaultConfig { minSdk = 24
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
EOF

echo "🔧 Building AAR…"
pushd "$MODULE_DIR" >/dev/null
[[ -f gradlew ]] || gradle wrapper --gradle-version 8.6 --distribution-type all
./gradlew -q clean bundleReleaseAar
popd >/dev/null

# ---------------------------------------------------------------------
# 6. Assemble distributable package
# ---------------------------------------------------------------------
echo "🚚 Bundling Kotlin package…"
rm -rf "$OUT_PKG" && mkdir -p "$OUT_PKG"
cp "$ROOT/LICENSE" "$OUT_PKG/"
cp "$ROOT/docs/readmes/kotlin/README.md" "$OUT_PKG/"
cp -R "$MODULE_DIR/build/outputs/aar" "$OUT_PKG/aar"
cp -R "$MODULE_DIR/src/main/java/dev/polkabind" "$OUT_PKG/src"

echo "✅ Success."
