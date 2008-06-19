VERSION=0.3.3

DESTDIR ?= /usr

all: 
	@echo "Nothing to do. make install|uninstall|clean|dist [DESTDIR=/usr]"

install:
	sed 's^prefix="/usr"^prefix="$(DESTDIR)"^g' yfksubs.pl > yfksubs2.pl 
	sed 's^prefix="/usr"^prefix="$(DESTDIR)"^g' yfk > yfk2 
	rm -f yfksubs.pl
	rm -f yfk
	mv yfksubs2.pl yfksubs.pl
	mv yfk2 yfk
	chmod 0755 yfk
	install -d -v				$(DESTDIR)/share/yfklog/
	install -d -v				$(DESTDIR)/share/yfklog/labels/
	install -d -v				$(DESTDIR)/bin/
	install -m 0755 yfk 		$(DESTDIR)/bin/ 
	install -m 0444 yfksubs.pl 	$(DESTDIR)/share/yfklog/
	install -m 0444 db_* 		$(DESTDIR)/share/yfklog/
	install -m 0444 cty.dat		$(DESTDIR)/share/yfklog/
	install -m 0444 config		$(DESTDIR)/share/yfklog/
	install -m 0444 p.png		$(DESTDIR)/share/yfklog/
	install -m 0444 *.lab		$(DESTDIR)/share/yfklog/labels/

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
	mkdir yfklog-$(VERSION)/onlinelog/
	cp yfk yfksubs.pl config cty.dat AUTHORS CHANGELOG db_*.sql *.sqlite THANKS \
	Makefile INSTALL MANUAL README p.png RELEASENOTES *.lab yfklog-$(VERSION)
	cp clubs/README yfklog-$(VERSION)/clubs
	cp clubs/hscmember.txt yfklog-$(VERSION)/clubs
	cp clubs/hsc2sql.awk yfklog-$(VERSION)/clubs
	cp onlinelog/README yfklog-$(VERSION)/onlinelog
	cp onlinelog/search.php yfklog-$(VERSION)/onlinelog
	cp onlinelog/test.txt yfklog-$(VERSION)/onlinelog
	tar -zcf yfklog-$(VERSION).tar.gz yfklog-$(VERSION)
	mv yfklog-$(VERSION) releases/
	mv yfklog-$(VERSION).tar.gz releases/
