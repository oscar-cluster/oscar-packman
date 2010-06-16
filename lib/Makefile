DESTDIR=

TOPDIR=..
include $(TOPDIR)/Config.mk

FILES := RPM.pm  DEB.pm
SUBDIRS := 

all:
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} all ) ; done

install:
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/OSCAR
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/OSCAR/PackMan
	install    -m 0755 ${FILES} $(DESTDIR)$(LIBDIR)/OSCAR/PackMan
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} install ) ; done

uninstall:
	cd $(DESTDIR)$(LIBDIR)/OSCAR; rm -f $(FILES)
	for dir in ${SUBDIRS} ; do ( cd $$dir ; ${MAKE} uninstall ) ; done

clean:
	@rm -f *~
