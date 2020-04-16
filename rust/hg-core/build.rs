// build.rs
//
// Copyright 2020 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

#[cfg(feature = "with-re2")]
use cc;

/// Uses either the system Re2 install as a dynamic library or the provided
/// build as a static library
#[cfg(feature = "with-re2")]
fn compile_re2() {
    use cc;
    use std::path::Path;
    use std::process::exit;

    let msg = r"HG_RE2_PATH must be one of `system|<path to build source clone of Re2>`";
    let re2 = match std::env::var_os("HG_RE2_PATH") {
        None => {
            eprintln!("{}", msg);
            exit(1)
        }
        Some(v) => {
            if v == "system" {
                None
            } else {
                Some(v)
            }
        }
    };

    let mut options = cc::Build::new();
    options
        .cpp(true)
        .flag("-std=c++11")
        .file("src/re2/rust_re2.cpp");

    if let Some(ref source) = re2 {
        options.include(Path::new(source));
    };

    options.compile("librustre.a");

    if let Some(ref source) = &re2 {
        // Link the local source statically
        println!(
            "cargo:rustc-link-search=native={}",
            Path::new(source).join(Path::new("obj")).display()
        );
        println!("cargo:rustc-link-lib=static=re2");
    } else {
        println!("cargo:rustc-link-lib=re2");
    }
}

fn main() {
    #[cfg(feature = "with-re2")]
    compile_re2();
}
