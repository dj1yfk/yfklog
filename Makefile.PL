# Copyright (C) 2008 Wes Hardaker
# License: GNU GPLv2.  See the COPYING file for details.
#!/usr/bin/perl

use ExtUtils::MakeMaker;

%opts = (
	 'NAME'		=> 'yfk',
	 'PREREQ_PM'    => { DBI => 0 },
	 'EXE_FILES'    => [qw(yfk)],
         'VERSION_FROM' => 'yfk',         # finds $VERSION
	);

if (!($^O eq 'MSWin32' || $Config{'ccflags'} =~ /-D_?WIN32_?/)) {
    # doesn't work on windows: no sed
    $opts{'PM_FILTER'} = 'sed -e "s|/usr/local|$(PREFIX)|"';
}

WriteMakefile(%opts);

sub MY::postamble {
    return '

YFKDIR=$(DESTDIR)$(PREFIX)/share/yfklog

INSTALL=$(PERL) "-MExtUtils::Command" -e cp

install:: installstuff installfixpaths

installstuff:
	$(MKPATH) $(YFKDIR)/labels
	$(INSTALL) yfksubs.pl db_* cty.dat config p.png $(YFKDIR)
	$(INSTALL) *.lab $(YFKDIR)/labels

installfixpaths:
	$(PERL) -p -i -e "s|/usr/local|$(PREFIX)|" $(DESTDIR)$(PREFIX)/bin/yfk
';
}
