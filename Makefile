BINDIR=usr/lib/perl5/OSCAR/
DEBTMP=/tmp/packman

all:
	

install:
	install -d -m 0755 $(DESTDIR)/$(BINDIR)
#	install -d -m 0755 ${DESTDIR}/$(BINDIR)/DepMan/
	install -d -m 0755 $(DESTDIR)/$(BINDIR)/PackMan/
#	install    -m 0755 DepMan.pm ${DESTDIR}/$(BINDIR)
	install    -m 0755 PackMan.pm $(DESTDIR)/$(BINDIR)
#	install    -m 0755 DepMan/UpdateDEBs.pm $(DESTDIR)/$(BINDIR)/DepMan/
#	install    -m 0755 DepMan/UpdateRPMs.pm $(DESTDIR)/$(BINDIR)/DepMan/
	install    -m 0755 PackMan/DEB.pm $(DESTDIR)/$(BINDIR)/PackMan/
	install    -m 0755 PackMan/RPM.pm $(DESTDIR)/$(BINDIR)/PackMan/

deb ::
	rm -rf $(DEBTMP)
	mkdir -p $(DEBTMP)
	cp -rf * $(DEBTMP)
	cd $(DEBTMP); dpkg-buildpackage -rfakeroot -uc -us

clean:
	
