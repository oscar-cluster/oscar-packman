LIBDIR ?= $(shell perl -V:vendorarch | sed s/vendorarch=\'\\/// | sed s/\'\;//)
