/*
re2.rs

Rust FFI bindings to Re2.

Copyright 2020 Valentin Gatien-Baron

This software may be used and distributed according to the terms of the
GNU General Public License version 2 or any later version.
*/
use libc::{c_int, c_void};

type Re2Ptr = *const c_void;

pub struct Re2(Re2Ptr);

/// `re2.h` says:
/// "An "RE2" object is safe for concurrent use by multiple threads."
unsafe impl Sync for Re2 {}

/// These bind to the C ABI in `rust_re2.cpp`.
extern "C" {
    fn rust_re2_create(data: *const u8, len: usize) -> Re2Ptr;
    fn rust_re2_destroy(re2: Re2Ptr);
    fn rust_re2_ok(re2: Re2Ptr) -> bool;
    fn rust_re2_error(
        re2: Re2Ptr,
        outdata: *mut *const u8,
        outlen: *mut usize,
    ) -> bool;
    fn rust_re2_match(
        re2: Re2Ptr,
        data: *const u8,
        len: usize,
        anchor: c_int,
    ) -> bool;
}

impl Re2 {
    pub fn new(pattern: &[u8]) -> Result<Re2, String> {
        unsafe {
            let re2 = rust_re2_create(pattern.as_ptr(), pattern.len());
            if rust_re2_ok(re2) {
                Ok(Re2(re2))
            } else {
                let mut data: *const u8 = std::ptr::null();
                let mut len: usize = 0;
                rust_re2_error(re2, &mut data, &mut len);
                Err(String::from_utf8_lossy(std::slice::from_raw_parts(
                    data, len,
                ))
                .to_string())
            }
        }
    }

    pub fn is_match(&self, data: &[u8]) -> bool {
        unsafe { rust_re2_match(self.0, data.as_ptr(), data.len(), 1) }
    }
}

impl Drop for Re2 {
    fn drop(&mut self) {
        unsafe { rust_re2_destroy(self.0) }
    }
}
