/*
 * bdiff.cc - fuzzer harness for bdiff.c
 *
 * Copyright 2018, Google Inc.
 *
 * This software may be used and distributed according to the terms of
 * the GNU General Public License, incorporated herein by reference.
 */
#include <memory>
#include <stdlib.h>

#include <fuzzer/FuzzedDataProvider.h>

extern "C" {
#include "bdiff.h"

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
	FuzzedDataProvider provider(Data, Size);
	std::string left = provider.ConsumeRandomLengthString(Size);
	std::string right = provider.ConsumeRemainingBytesAsString();

	struct bdiff_line *a, *b;
	int an = bdiff_splitlines(left.c_str(), left.size(), &a);
	int bn = bdiff_splitlines(right.c_str(), right.size(), &b);
	struct bdiff_hunk l;
	bdiff_diff(a, an, b, bn, &l);
	free(a);
	free(b);
	bdiff_freehunks(l.next);
	return 0; // Non-zero return values are reserved for future use.
}

#ifdef HG_FUZZER_INCLUDE_MAIN
int main(int argc, char **argv)
{
	const char data[] = "asdf";
	return LLVMFuzzerTestOneInput((const uint8_t *)data, 4);
}
#endif

} // extern "C"
