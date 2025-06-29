use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    // Re-run build.rs if the core crate’s API changes
    println!("cargo:rerun-if-changed=../polkabind-core/src/lib.rs");

    // Out dir
    let out_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../bindings");

    // Swift bindings:
    let status = Command::new("uniffi-bindgen")
        .args(&[
            "generate",
            "--language",
            "swift",
            "--annotations",
            "--out-dir",
            out_dir.join("swift").to_str().unwrap(),
            // point at your Rust lib
            "../polkabind-core/src/lib.rs",
        ])
        .status()
        .expect("failed to run uniffi-bindgen for Swift");
    assert!(status.success(), "Swift binding generation failed");

    // Kotlin bindings:
    let status = Command::new("uniffi-bindgen")
        .args(&[
            "generate",
            "--language",
            "kotlin",
            "--annotations",
            "--out-dir",
            out_dir.join("kotlin/uniffi").to_str().unwrap(),
            "../polkabind-core/src/lib.rs",
        ])
        .status()
        .expect("failed to run uniffi-bindgen for Kotlin");
    assert!(status.success(), "Kotlin binding generation failed");
}
