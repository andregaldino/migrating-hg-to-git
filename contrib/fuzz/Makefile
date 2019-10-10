CC = clang
CXX = clang++

all: bdiff mpatch xdiff

fuzzutil.o: fuzzutil.cc fuzzutil.h
	$(CXX) $(CXXFLAGS) -g -O1 \
	  -std=c++17 \
	  -I../../mercurial -c -o fuzzutil.o fuzzutil.cc

fuzzutil-oss-fuzz.o: fuzzutil.cc fuzzutil.h
	$(CXX) $(CXXFLAGS) -std=c++17 \
	  -I../../mercurial -c -o fuzzutil-oss-fuzz.o fuzzutil.cc

pyutil.o: pyutil.cc pyutil.h
	$(CXX) $(CXXFLAGS) -g -O1 \
	  `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial -c -o pyutil.o pyutil.cc

bdiff.o: ../../mercurial/bdiff.c
	$(CC) $(CFLAGS) -fsanitize=fuzzer-no-link,address -c -o bdiff.o \
	  ../../mercurial/bdiff.c

bdiff: bdiff.cc bdiff.o fuzzutil.o
	$(CXX) $(CXXFLAGS) -DHG_FUZZER_INCLUDE_MAIN=1 -g -O1 -fsanitize=fuzzer-no-link,address \
	  -std=c++17 \
	  -I../../mercurial bdiff.cc bdiff.o fuzzutil.o -o bdiff

bdiff-oss-fuzz.o: ../../mercurial/bdiff.c
	$(CC) $(CFLAGS) -c -o bdiff-oss-fuzz.o ../../mercurial/bdiff.c

bdiff_fuzzer: bdiff.cc bdiff-oss-fuzz.o fuzzutil-oss-fuzz.o
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial bdiff.cc \
	  bdiff-oss-fuzz.o fuzzutil-oss-fuzz.o -lFuzzingEngine -o \
	  $$OUT/bdiff_fuzzer

mpatch.o: ../../mercurial/mpatch.c
	$(CC) -g -O1 -fsanitize=fuzzer-no-link,address -c -o mpatch.o \
	  ../../mercurial/mpatch.c

mpatch: CXXFLAGS += -std=c++17
mpatch: mpatch.cc mpatch.o fuzzutil.o
	$(CXX) $(CXXFLAGS) -DHG_FUZZER_INCLUDE_MAIN=1 -g -O1 -fsanitize=fuzzer-no-link,address \
	  -I../../mercurial mpatch.cc mpatch.o fuzzutil.o -o mpatch

mpatch-oss-fuzz.o: ../../mercurial/mpatch.c
	$(CC) $(CFLAGS) -c -o mpatch-oss-fuzz.o ../../mercurial/mpatch.c

mpatch_fuzzer: mpatch.cc mpatch-oss-fuzz.o fuzzutil-oss-fuzz.o
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial mpatch.cc \
	  mpatch-oss-fuzz.o fuzzutil-oss-fuzz.o -lFuzzingEngine -o \
	  $$OUT/mpatch_fuzzer

mpatch_corpus.zip:
	python mpatch_corpus.py $$OUT/mpatch_fuzzer_seed_corpus.zip

x%.o: ../../mercurial/thirdparty/xdiff/x%.c ../../mercurial/thirdparty/xdiff/*.h
	$(CC) -g -O1 -fsanitize=fuzzer-no-link,address -c \
	  -o $@ \
	  $<

xdiff: CXXFLAGS += -std=c++17
xdiff: xdiff.cc xdiffi.o xprepare.o xutils.o fuzzutil.o
	$(CXX) $(CXXFLAGS) -DHG_FUZZER_INCLUDE_MAIN=1 -g -O1 -fsanitize=fuzzer-no-link,address \
	  -I../../mercurial xdiff.cc \
	  xdiffi.o xprepare.o xutils.o fuzzutil.o -o xdiff

fuzz-x%.o: ../../mercurial/thirdparty/xdiff/x%.c ../../mercurial/thirdparty/xdiff/*.h
	$(CC) $(CFLAGS) -c \
	  -o $@ \
	  $<

xdiff_fuzzer: xdiff.cc fuzz-xdiffi.o fuzz-xprepare.o fuzz-xutils.o fuzzutil-oss-fuzz.o
	$(CXX) $(CXXFLAGS) -std=c++17 -I../../mercurial xdiff.cc \
	  fuzz-xdiffi.o fuzz-xprepare.o fuzz-xutils.o fuzzutil-oss-fuzz.o \
	  -lFuzzingEngine -o $$OUT/xdiff_fuzzer

manifest.o: ../../mercurial/cext/manifest.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o manifest.o ../../mercurial/cext/manifest.c

charencode.o: ../../mercurial/cext/charencode.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o charencode.o ../../mercurial/cext/charencode.c

parsers.o: ../../mercurial/cext/parsers.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o parsers.o ../../mercurial/cext/parsers.c

dirs.o: ../../mercurial/cext/dirs.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o dirs.o ../../mercurial/cext/dirs.c

pathencode.o: ../../mercurial/cext/pathencode.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o pathencode.o ../../mercurial/cext/pathencode.c

revlog.o: ../../mercurial/cext/revlog.c
	$(CC) $(CFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -I../../mercurial \
	  -c -o revlog.o ../../mercurial/cext/revlog.c

dirs_fuzzer: dirs.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial dirs.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/dirs_fuzzer

fncache_fuzzer: fncache.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial fncache.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/fncache_fuzzer

manifest_corpus.zip:
	python manifest_corpus.py $$OUT/manifest_fuzzer_seed_corpus.zip

manifest_fuzzer: manifest.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial manifest.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/manifest_fuzzer

revlog_fuzzer: revlog.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial revlog.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/revlog_fuzzer

revlog_corpus.zip:
	python revlog_corpus.py $$OUT/revlog_fuzzer_seed_corpus.zip

dirstate_fuzzer: dirstate.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial dirstate.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/dirstate_fuzzer

dirstate_corpus.zip:
	python dirstate_corpus.py $$OUT/dirstate_fuzzer_seed_corpus.zip

fm1readmarkers_fuzzer: fm1readmarkers.cc manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o
	$(CXX) $(CXXFLAGS) `$$OUT/sanpy/bin/python-config --cflags` \
	  -Wno-register -Wno-macro-redefined \
	  -I../../mercurial fm1readmarkers.cc \
	  manifest.o charencode.o parsers.o dirs.o pathencode.o revlog.o pyutil.o \
	  -lFuzzingEngine `$$OUT/sanpy/bin/python-config --ldflags` \
	  -o $$OUT/fm1readmarkers_fuzzer

fm1readmarkers_corpus.zip:
	python fm1readmarkers_corpus.py $$OUT/fm1readmarkers_fuzzer_seed_corpus.zip

clean:
	$(RM) *.o *_fuzzer \
	  bdiff \
	  mpatch \
	  xdiff

oss-fuzz: bdiff_fuzzer mpatch_fuzzer mpatch_corpus.zip xdiff_fuzzer dirs_fuzzer fncache_fuzzer manifest_fuzzer manifest_corpus.zip revlog_fuzzer revlog_corpus.zip dirstate_fuzzer dirstate_corpus.zip fm1readmarkers_fuzzer fm1readmarkers_corpus.zip

.PHONY: all clean oss-fuzz
