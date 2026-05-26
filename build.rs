fn main() {
    // Compile the Objective-C speech-recognition helper (macOS only).
    // Gives us a thin C API over SFSpeechRecognizer without heavy ObjC crates.
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "macos" {
        cc::Build::new()
            .file("src/speech.m")
            .flag("-fobjc-arc")
            .compile("flowey_speech");

        println!("cargo:rustc-link-lib=framework=Speech");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=ApplicationServices");

        // Embed Info.plist into the binary so macOS TCC finds the privacy-usage
        // descriptions even when running the raw dev binary (not a bundled .app).
        let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let plist = format!("{manifest}/Info.plist");
        println!("cargo:rustc-link-arg=-sectcreate");
        println!("cargo:rustc-link-arg=__TEXT");
        println!("cargo:rustc-link-arg=__info_plist");
        println!("cargo:rustc-link-arg={plist}");
        println!("cargo:rerun-if-changed=Info.plist");
    }

    tauri_build::build();
}
