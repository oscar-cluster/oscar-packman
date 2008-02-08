BINDIR=usr/lib/perl5/OSCAR

all:
	

install:
	install -d -m 0755 $(DESTDIR)/$(BINDIR)
#	install -d -m 0755 ${DESTDIR}/$(BINDIR)/DepMan/
	install -d -m 0755 $(DESTDIR)/$(BINDIR)/PackMan
#	install    -m 0755 DepMan.pm ${DESTDIR}/$(BINDIR)
	install    -m 0755 PackMan.pm $(DESTDIR)/$(BINDIR)
	install    -m 0755 PackManDefs.pm $(DESTDIR)/$(BINDIR)
#	install    -m 0755 DepMan/UpdateDEBs.pm $(DESTDIR)/$(BINDIR)/DepMan/
#	install    -m 0755 DepMan/UpdateRPMs.pm $(DESTDIR)/$(BINDIR)/DepMan/
	install    -m 0755 PackMan/DEB.pm $(DESTDIR)/$(BINDIR)/PackMan/
	install    -m 0755 PackMan/RPM.pm $(DESTDIR)/$(BINDIR)/PackMan/

deb ::
	dpkg-buildpackage -rfakeroot 

clean:
	
