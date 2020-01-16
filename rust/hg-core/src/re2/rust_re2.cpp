/*
rust_re2.cpp

C ABI export of Re2's C++ interface for Rust FFI.

Copyright 2020 Valentin Gatien-Baron

This software may be used and distributed according to the terms of the
GNU General Public License version 2 or any later version.
*/

#include <re2/re2.h>
using namespace re2;

extern "C" {
	RE2* rust_re2_create(const char* data, size_t len) {
		RE2::Options o;
		o.set_encoding(RE2::Options::Encoding::EncodingLatin1);
		o.set_log_errors(false);
		o.set_max_mem(50000000);

		return new RE2(StringPiece(data, len), o);
	}

	void rust_re2_destroy(RE2* re) {
		delete re;
	}

	bool rust_re2_ok(RE2* re) {
		return re->ok();
	}

	void rust_re2_error(RE2* re, const char** outdata, size_t* outlen) {
		const std::string& e = re->error();
		*outdata = e.data();
		*outlen = e.length();
	}

	bool rust_re2_match(RE2* re, char* data, size_t len, int ianchor) {
		const StringPiece sp = StringPiece(data, len);

		RE2::Anchor anchor =
			ianchor == 0 ? RE2::Anchor::UNANCHORED :
			(ianchor == 1 ? RE2::Anchor::ANCHOR_START :
			 RE2::Anchor::ANCHOR_BOTH);

		return re->Match(sp, 0, len, anchor, NULL, 0);
	}
}
