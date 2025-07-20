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
  *)      EXT=so    ;;
esac

RUST_DYLIB="$ROOT/target/release/libpolkabind.$EXT"

# Android ABIs to target
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

cd "$ROOT"

# 0)   Build host dylib *before* the Android loop ─────────────
echo "🔨 Building host dylib first…"
if [[ "$(uname)" != "Darwin" ]]; then
  export RUSTFLAGS="-C link-arg=-Wl,--export-dynamic"
fi
cargo build --release
unset RUSTFLAGS
[[ -f "$RUST_DYLIB" ]]

# ——— 1) Generate Kotlin glue ———
echo "🧹 Generating Kotlin bindings…"
rm -rf "$BINDINGS"
mkdir -p "$BINDINGS"
"$UNIFFI_BIN" generate \
  --config "$ROOT/uniffi.toml" \
  --no-format \
  --library "$RUST_DYLIB" \
  --language kotlin \
  --out-dir "$BINDINGS"

GLUE_SRC="$BINDINGS/dev/polkabind/polkabind.kt"
if [[ ! -f "$GLUE_SRC" ]]; then
  echo "❌ UniFFI didn’t emit polkabind.kt"
  exit 1
fi

# ——— 2) Cross-compile Rust for Android ABIs ———
echo "🛠️  Cross-compiling Rust for Android ABIs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac

  cargo ndk --target "$TARGET" --platform 21 build --release
  if [[ ! -f "$ROOT/target/${TARGET}/release/libpolkabind.so" ]]; then
    echo "❌ missing libpolkabind.so for $TARGET"
    exit 1
  fi
done

# ——— 3) Build uniffi-bindgen tool ———
echo "🔨 Building uniffi-bindgen…"
cargo build --release -p polkabind-bindgen
[[ -x "$UNIFFI_BIN" ]] || { echo "❌ missing bindgen tool $UNIFFI_BIN"; exit 1; }

# ——— 4) Build the host cdylib with embedded metadata ———
echo "🛠️  Building Rust host library (the root polkabind crate)…"
cargo build --release --manifest-path "$ROOT/Cargo.toml"
[[ -f "$RUST_DYLIB" ]] || { echo "❌ missing host library $RUST_DYLIB"; exit 1; }

# ——— 5) Lay out Android library module ———
echo "📂 Setting up Android library module…"
MODULE_DIR="$OUT_LIBMODULE/polkabind-android"
rm -rf "$MODULE_DIR"

# create sources & jniLibs dirs
mkdir -p "$MODULE_DIR/src/main/java/dev/polkabind"
for ABI in "${ABIS[@]}"; do
  mkdir -p "$MODULE_DIR/src/main/jniLibs/$ABI"
done

# copy the generated Kotlin glue
cp "$GLUE_SRC" "$MODULE_DIR/src/main/java/dev/polkabind/"

# copy each ABI’s .so into jniLibs
echo "📂 Copying .so into jniLibs…"
for ABI in "${ABIS[@]}"; do
  case $ABI in
    arm64-v8a)   TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7-linux-androideabi ;;
    x86_64)      TARGET=x86_64-linux-android ;;
    x86)         TARGET=i686-linux-android ;;
  esac
  SRC="$ROOT/target/${TARGET}/release/libpolkabind.so"
  DST="$MODULE_DIR/src/main/jniLibs/$ABI/libpolkabind.so"
  cp "$SRC" "$DST"
done

# ——— 6) Create settings.gradle.kts ———
cat > "$MODULE_DIR/settings.gradle.kts" <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.library") version "8.4.0"
        kotlin("android")          version "1.9.20"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "polkabind-android"
EOF

# ——— 7) Create build.gradle.kts ———
cat > "$MODULE_DIR/build.gradle.kts" <<'EOF'
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
plugins {
    id("com.android.library")
    kotlin("android")
    id("maven-publish")
}

dependencies {
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.6.4")
}

android {
    namespace = "dev.polkabind"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a","armeabi-v7a","x86_64","x86")
        }
    }

    publishing {
        singleVariant("release")
    }

    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

afterEvaluate {
  publishing {
    publications {
      create<MavenPublication>("release") {
        groupId    = "dev.polkabind"
        artifactId = "polkabind-android"
        version    = "1.0.0-SNAPSHOT"
        from(components["release"])
      }
    }
    repositories {
      maven { url = uri("$rootDir/../../PolkabindKotlin/maven-snapshots") }
    }
  }
}

tasks.withType<KotlinCompile> {
    kotlinOptions.jvmTarget = "1.8"
}
EOF

# ——— 8) Bootstrap Gradle wrapper & build AAR ———
echo "🔧 Bootstrapping Gradle wrapper & building AAR…"
pushd "$MODULE_DIR" >/dev/null
if [[ ! -f gradlew ]]; then
  gradle wrapper --gradle-version 8.6 --distribution-type all
fi
./gradlew clean bundleReleaseAar publishToMavenLocal
popd >/dev/null

# ——— 9) Package minimal Kotlin artifact ———
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
