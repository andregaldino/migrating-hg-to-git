CC = clang
CXX = clang++

# By default, use our own standalone_fuzz_target_runner.
# This runner does no fuzzing, but simply executes the inputs
# provided via parameters.
# Run e.g. "make all LIB_FUZZING_ENGINE=/path/to/libFuzzer.a"
# to link the fuzzer(s) against a real fuzzing engine.
#
# OSS-Fuzz will define its own value for LIB_FUZZING_ENGINE.
LIB_FUZZING_ENGINE ?= standalone_fuzz_target_runner.o

PYTHON_CONFIG ?= $$OUT/sanpy/bin/python-config

CXXFLAGS += -Wno-deprecated-register

all: standalone_fuzz_target_runner.o oss-fuzz

standalone_fuzz_target_runner.o: standalone_fuzz_target_runner.cc

pyutil.o: pyutil.cc pyutil.h
	$(CXX) $(CXXFLAGS) -g -O1 \
	  `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial -c -o pyutil.o pyutil.cc

bdiff-oss-fuzz.o: ../../mercurial/bdiff.c
	$(CC) $(CFLAGS) -c -o bdiff-oss-fuzz.o ../../mercurial/bdiff.c

bdiff_fuzzer: bdiff.cc bdiff-oss-fuzz.o
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial bdiff.cc \
	  bdiff-oss-fuzz.o $(LIB_FUZZING_ENGINE) -o \
	  $$OUT/bdiff_fuzzer

mpatch.o: ../../mercurial/mpatch.c
	$(CC) -g -O1 -fsanitize=fuzzer-no-link,address -c -o mpatch.o \
	  ../../mercurial/mpatch.c

mpatch-oss-fuzz.o: ../../mercurial/mpatch.c
	$(CC) $(CFLAGS) -c -o mpatch-oss-fuzz.o ../../mercurial/mpatch.c

mpatch_fuzzer: mpatch.cc mpatch-oss-fuzz.o 
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial mpatch.cc \
	  mpatch-oss-fuzz.o $(LIB_FUZZING_ENGINE) -o \
	  $$OUT/mpatch_fuzzer

mpatch_corpus.zip:
	python mpatch_corpus.py $$OUT/mpatch_fuzzer_seed_corpus.zip

fuzz-x%.o: ../../mercurial/thirdparty/xdiff/x%.c ../../mercurial/thirdparty/xdiff/*.h
	$(CC) $(CFLAGS) -c \
	  -o $@ \
	  $<

xdiff_fuzzer: xdiff.cc fuzz-xdiffi.o fuzz-xprepare.o fuzz-xutils.o 
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial xdiff.cc \
	  fuzz-xdiffi.o fuzz-xprepare.o fuzz-xutils.o \
	  $(LIB_FUZZING_ENGINE) -o $$OUT/xdiff_fuzzer

manifest.o: ../../mercurial/cext/manifest.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o manifest.o ../../mercurial/cext/manifest.c

charencode.o: ../../mercurial/cext/charencode.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o charencode.o ../../mercurial/cext/charencode.c

parsers.o: ../../mercurial/cext/parsers.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o parsers.o ../../mercurial/cext/parsers.c

dirs.o: ../../mercurial/cext/dirs.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o dirs.o ../../mercurial/cext/dirs.c

pathencode.o: ../../mercurial/cext/pathencode.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o pathencode.o ../../mercurial/cext/pathencode.c

revlog.o: ../../mercurial/cext/revlog.c
	$(CC) $(CFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -I../../mercurial \
	  -c -o revlog.o ../../mercurial/cext/revlog.c

dirs_fuzzer: dirs.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial dirs.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/dirs_fuzzer

fncache_fuzzer: fncache.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial fncache.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/fncache_fuzzer

jsonescapeu8fast_fuzzer: jsonescapeu8fast.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial jsonescapeu8fast.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/jsonescapeu8fast_fuzzer

manifest_corpus.zip:
	python manifest_corpus.py $$OUT/manifest_fuzzer_seed_corpus.zip

manifest_fuzzer: manifest.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial manifest.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/manifest_fuzzer

revlog_fuzzer: revlog.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial revlog.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/revlog_fuzzer

revlog_corpus.zip:
	python revlog_corpus.py $$OUT/revlog_fuzzer_seed_corpus.zip

dirstate_fuzzer: dirstate.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial dirstate.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/dirstate_fuzzer

dirstate_corpus.zip:
	python dirstate_corpus.py $$OUT/dirstate_fuzzer_seed_corpus.zip

fm1readmarkers_fuzzer: fm1readmarkers.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$(PYTHON_CONFIG) --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial fm1readmarkers.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  $(LIB_FUZZING_ENGINE) `$(PYTHON_CONFIG) --ldflags` \
	  -o $$OUT/fm1readmarkers_fuzzer

fm1readmarkers_corpus.zip:
	python fm1readmarkers_corpus.py $$OUT/fm1readmarkers_fuzzer_seed_corpus.zip

clean:
	$(RM) *.o *_fuzzer \
	  bdiff \
	  mpatch \
	  xdiff

oss-fuzz: bdiff_fuzzer mpatch_fuzzer mpatch_corpus.zip xdiff_fuzzer dirs_fuzzer fncache_fuzzer jsonescapeu8fast_fuzzer manifest_fuzzer manifest_corpus.zip revlog_fuzzer revlog_corpus.zip dirstate_fuzzer dirstate_corpus.zip fm1readmarkers_fuzzer fm1readmarkers_corpus.zip

.PHONY: all clean oss-fuzz
