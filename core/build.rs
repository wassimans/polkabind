fn main() {
    // Rerun build.rs whenever lib.rs changes:
    //     println!("cargo:rerun-if-changed=src/lib.rs");

    //     // Path to the input Rust file containing all #[uniffi::export] annotations
    //     let input = "src/lib.rs";

    //     // Output directory for generated UDL + language bindings:
    //     let out_dir = std::env::var("OUT_DIR").unwrap();
    //     let out_bindings = format!("{}/bindings", out_dir);

    //     // Generate UDL file:
    //     uniffi_bindgen::generate_uniffi_ddl(input, &format!("{}/polkabind.udl", out_dir)).unwrap();

    //     // Generate Swift/Kotlin stubs:
    //     uniffi_bindgen::generate_bindings(
    //         &format!("{}/polkabind.udl", out_dir),
    //         Some(uniffi_bindgen::LanguageConfiguration {
    //             swift: Some(uniffi_bindgen::SwiftConfig {
    //                 out_path: &format!("{}/Swift", out_bindings),
    //                 ..Default::default()
    //             }),
    //             kotlin: Some(uniffi_bindgen::KotlinConfig {
    //                 out_path: &format!("{}/Kotlin", out_bindings),
    //                 ..Default::default()
    //             }),
    //             ..Default::default()
    //         }),
    //     )
    //     .unwrap();
}
