SOURCES=$(notdir $(wildcard ../mercurial/helptext/*.[0-9].txt))
MAN=$(SOURCES:%.txt=%)
HTML=$(SOURCES:%.txt=%.html)
GENDOC=gendoc.py ../mercurial/commands.py ../mercurial/help.py \
	../mercurial/helptext/*.txt ../hgext/*.py ../hgext/*/__init__.py
PREFIX=/usr/local
MANDIR=$(PREFIX)/share/man
INSTALL=install -m 644
# Default to Python 3.
#
# Windows ships Python 3 as `python.exe`, which may not be on PATH.  py.exe is.
ifeq ($(OS),Windows_NT)
PYTHON?=py -3
else
PYTHON?=python3
endif
RSTARGS=

export HGENCODING=UTF-8

all: man html

man: $(MAN)

html: $(HTML)

# This logic is duplicated in setup.py:hgbuilddoc()
common.txt $(SOURCES) $(SOURCES:%.txt=%.gendoc.txt): $(GENDOC)
	${PYTHON} gendoc.py "$(basename $@)" > $@.tmp
	mv $@.tmp $@

%: %.txt %.gendoc.txt common.txt
	$(PYTHON) runrst hgmanpage $(RSTARGS) --halt warning \
	  --strip-elements-with-class htmlonly $*.txt $*

%.html: %.txt %.gendoc.txt common.txt
	$(PYTHON) runrst html $(RSTARGS) --halt warning \
	  --link-stylesheet --stylesheet-path style.css $*.txt $*.html

MANIFEST: man html
# tracked files are already in the main MANIFEST
	$(RM) $@
	for i in $(MAN) $(HTML); do \
	  echo "doc/$$i" >> $@ ; \
	done

install: man
	for i in $(MAN) ; do \
	  subdir=`echo $$i | sed -n 's/^.*\.\([0-9]\)$$/man\1/p'` ; \
	  mkdir -p "$(DESTDIR)$(MANDIR)"/$$subdir ; \
	  $(INSTALL) $$i "$(DESTDIR)$(MANDIR)"/$$subdir ; \
	done

clean:
	$(RM) $(MAN) $(HTML) common.txt $(SOURCES) $(SOURCES:%.txt=%.gendoc.txt) MANIFEST
