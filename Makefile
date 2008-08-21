include ./Config.mk
BINDIR=usr/bin
MANDIR=usr/share/man/man3
OSCARLIBDIR=$(LIBDIR)/OSCAR

all:
	/usr/bin/pod2man --section=3 PackMan.pm       | gzip > PackMan.3.gz
	/usr/bin/pod2man --section=3 PackMan/RPM.pm   | gzip > PackMan-RPM.3.gz
	/usr/bin/pod2man --section=3 PackMan/DEB.pm   | gzip > PackMan-DEB.3.gz
	

install:
	@echo "Installing Perl modules in $(OSCARLIBDIR)"
	@install -d -m 0755 $(DESTDIR)/$(OSCARLIBDIR)
	@install -d -m 0755 $(DESTDIR)/$(OSCARLIBDIR)/PackMan/
	@install -d -m 0755 $(DESTDIR)/$(BINDIR)
	@install -d -m 0755 $(DESTDIR)/$(MANDIR)
	@install    -m 0755 packman               $(DESTDIR)/$(BINDIR)
	@install    -m 0755 PackMan.pm            $(DESTDIR)/$(OSCARLIBDIR)
	@install    -m 0755 PackManDefs.pm        $(DESTDIR)/$(OSCARLIBDIR)
	@install    -m 0755 PackMan/DEB.pm        $(DESTDIR)/$(OSCARLIBDIR)/PackMan/
	@install    -m 0755 PackMan/RPM.pm        $(DESTDIR)/$(OSCARLIBDIR)/PackMan/
	@install    -m 0644 PackMan.3.gz          $(DESTDIR)/$(MANDIR)
	@install    -m 0644 PackMan-RPM.3.gz      $(DESTDIR)/$(MANDIR)
	@install    -m 0644 PackMan-DEB.3.gz      $(DESTDIR)/$(MANDIR)

deb ::
	dpkg-buildpackage -rfakeroot 

clean:
	rm -f PackMan.3.gz PackMan-RPM.3.gz PackMan-DEB.3.gz
	rm -f build-stamp configure-stamp
	rm -rf debian/files debian/packman
	rm -f ./packman.tar.gz

dist: clean
	rm -rf /tmp/packman
	mkdir /tmp/packman
	cp -rf * /tmp/packman
	cd /tmp/packman; rm -rf `find . -name .svn`
	cd /tmp; tar czf ./packman.tar.gz packman
	mv /tmp/packman.tar.gz .
