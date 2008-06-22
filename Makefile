LIBDIR=usr/lib/perl5/OSCAR/
BINDIR=usr/bin

all:
	

install:
	install -d -m 0755 $(DESTDIR)/$(LIBDIR)
	install -d -m 0755 $(DESTDIR)/$(LIBDIR)/PackMan/
	install -d -m 0755 $(DESTDIR)/$(BINDIR)
	install    -m 0755 packman $(DESTDIR)/$(BINDIR)
	install    -m 0755 PackMan.pm $(DESTDIR)/$(LIBDIR)
	install    -m 0755 PackManDefs.pm $(DESTDIR)/$(LIBDIR)
	install    -m 0755 PackMan/DEB.pm $(DESTDIR)/$(LIBDIR)/PackMan/
	install    -m 0755 PackMan/RPM.pm $(DESTDIR)/$(LIBDIR)/PackMan/

deb ::
	dpkg-buildpackage -rfakeroot 

clean:
	
