ARCH ?= x86_64

CCEXTRAS="-Wall -Wextra"

ifeq ($(ARCH),x86_64)
	LIBDIRSUFFIX = 64
else
	LIBDIRSUFFIX = ""
endif

all: mo depfinder-search

mo:
	for i in `ls po/*.po`; do \
		msgfmt $$i -o `echo $$i | sed "s/\.po//"`.mo; \
	done

depfinder-search:
	$(MAKE) -C depfinder-search/

install:
	install -d -m 755 $(DESTDIR)/usr/bin
	install -d -m 755 $(DESTDIR)/usr/libexec
	install -m 755 depfinder $(DESTDIR)/usr/bin/
	sed -i "s/^LIBDIRSUFFIX=.*/LIBDIRSUFFIX=\"$(LIBDIRSUFFIX)\"/" \
		$(DESTDIR)/usr/bin/depfinder
	install -m 755 depfinder-search/depfinder-search $(DESTDIR)/usr/libexec/
	install -d -m 755 $(DESTDIR)/usr/man/man1
	install -m 644 man/depfinder.man $(DESTDIR)/usr/man/man1/depfinder.1
	for i in `ls po/*.po|sed "s/po\/\(.*\)\.po/\1/"`; do \
		install -D -m 644 po/$$i.mo \
		$(DESTDIR)/usr/share/locale/$$i/LC_MESSAGES/depfinder.mo; \
	done

clean:
	rm -f po/*.mo
	$(MAKE) clean -C depfinder-search/

.PHONY: install clean depfinder-search mo
