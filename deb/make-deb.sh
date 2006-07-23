#!/bin/sh
#
#
# Copyright (c) 2006 Oak Ridge National Laboratory, Geoffroy Vallee <valleegr@ornl.gov>
#                    All rights reserved
#
#   This file is part of the OSCAR software package.  For license
#   information, see the COPYING file in the top level directory of the
#   OSCAR source distribution.
#

# we get the version number from the debian/control file. This file must be updated before the creation of a new package
version_number=`grep "Standards-Version:" debian/control | sed 's/Standards-Version: //' | sed 's/ //'`
path=`pwd`

echo "Be sure before to create the package that package information is up-to-date."
echo "Read the file deb/README for more details."
echo "Press enter to continue or Ctrl+C to abord."
read $toto

echo "Creating Debian package for Packman/Depman version " ${version_number}"."

# we first copy everything in /tmp/deb-packman and prepare a directory for packaging
rm -rf /tmp/deb-packman
mkdir -p /tmp/deb-packman/packman-${version_number}
ls -l /tmp/deb-packman/packman-${version_number}
cp -rf ../* /tmp/deb-packman/packman-${version_number}
cp -f Makefile /tmp/deb-packman/packman-${version_number}
rm -rf /tmp/deb-packman/packman-${version_number}/deb
rm -f /tmp/deb-packman/packman-${version_number}/packman-depman.spec

# Then we create the tarball used to create the package
tar czf /tmp/deb-packman/packman-${version_number}.tar.gz /tmp/deb-packman/packman-${version_number}

cd  /tmp/deb-packman/packman-${version_number}

# We clean up the stub
rm -f debian/*.ex debian/*.EX

# We create all the files for the package
echo "Executing dh_make..."
dh_make -c gpl --single  

# A complete tree of directories is now ready. We update that thanks to information we already have.
cd $path
cp -f debian/control /tmp/deb-packman/packman-${version_number}/debian
cp -f debian/copyright /tmp/deb-packman/packman-${version_number}/debian
cp -f debian/changelog /tmp/deb-packman/packman-${version_number}/debian

# we then really create the package
cd  /tmp/deb-packman/packman-${version_number}
echo "Executing dpkg-buildpackage -rfakeroot"
ret=`/usr/bin/dpkg-buildpackage -rfakeroot -uc -us`

# then we grab the created files :-)
cd .. 
cp -rf *.changes *.deb *.orig.tar.gz $path
rm -rf /tmp/deb-packman

echo "Package(s) created and available in the deb directory"

