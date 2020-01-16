// build.rs
//
// Copyright 2020 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

#[cfg(feature = "with-re2")]
use cc;

#[cfg(feature = "with-re2")]
fn compile_re2() {
    cc::Build::new()
        .cpp(true)
        .flag("-std=c++11")
        .file("src/re2/rust_re2.cpp")
        .compile("librustre.a");

    println!("cargo:rustc-link-lib=re2");
}

fn main() {
    #[cfg(feature = "with-re2")]
    compile_re2();
}
