VERSION=0.6.0

DESTDIR ?= /usr

.PHONY: install uninstall clean dist

all: 
	@echo "Nothing to do. make install|uninstall|clean|dist [DESTDIR=/usr]"

install:
	sed 's^prefix="/usr"^prefix="$(DESTDIR)"^g' yfksubs.pl > yfksubs2.pl 
	sed 's^prefix="/usr"^prefix="$(DESTDIR)"^g' yfk > yfk2 
	chmod 0755 yfk
	install -d  				$(DESTDIR)/share/yfklog/
	install -d  				$(DESTDIR)/share/doc/yfklog/doc/
	install -d  				$(DESTDIR)/share/yfklog/labels/
	install -d  				$(DESTDIR)/bin/
	install -m 0755 yfk2		$(DESTDIR)/bin/yfk 
	install -m 0444 yfksubs2.pl	$(DESTDIR)/share/yfklog/yfksubs.pl
	install -m 0444 db_* 		$(DESTDIR)/share/yfklog/
	install -m 0444 cty.dat		$(DESTDIR)/share/yfklog/
	install -m 0444 config		$(DESTDIR)/share/yfklog/
	install -m 0444 p.png		$(DESTDIR)/share/yfklog/
	install -m 0444 *.lab		$(DESTDIR)/share/yfklog/labels/
	install -m 0444 doc/*		$(DESTDIR)/share/doc/yfklog/doc/
	rm -f yfksubs2.pl
	rm -f yfk2

uninstall:
	rm -f  $(DESTDIR)/bin/yfk
	rm -rf $(DESTDIR)/share/yfklog/

clean:
	rm -f *~ 

dist:
	sed 's/Version [0-9].[0-9].[0-9]/Version $(VERSION)/g' README > README2
	rm -f README
	mv README2 README
	sed 's/Version [0-9].[0-9].[0-9]/Version $(VERSION)/g' MANUAL > MANUAL2
	rm -f MANUAL
	mv MANUAL2 MANUAL
	rm -f releases/yfklog-$(VERSION).tar.gz
	rm -rf releases/yfklog-$(VERSION)
	mkdir yfklog-$(VERSION)
	mkdir yfklog-$(VERSION)/clubs/
	mkdir yfklog-$(VERSION)/doc/
	mkdir yfklog-$(VERSION)/onlinelog/
	cp yfk yfksubs.pl config cty.dat AUTHORS CHANGELOG db_*.sql *.sqlite \
		COPYING Makefile\
	 INSTALL MANUAL README p.png RELEASENOTES *.lab yfklog-$(VERSION)
	cp clubs/README yfklog-$(VERSION)/clubs
	cp onlinelog/README yfklog-$(VERSION)/onlinelog
	cp onlinelog/search.php yfklog-$(VERSION)/onlinelog
	cp onlinelog/test.txt yfklog-$(VERSION)/onlinelog
	cp doc/*.html yfklog-$(VERSION)/doc
	cp doc/*.png yfklog-$(VERSION)/doc
	cp doc/*.jpg yfklog-$(VERSION)/doc
	tar -zcf yfklog-$(VERSION).tar.gz yfklog-$(VERSION)
	mv yfklog-$(VERSION) releases/
	mv yfklog-$(VERSION).tar.gz releases/
	md5sum releases/*.tar.gz > releases/md5sums.txt
	chmod a+r releases/*
