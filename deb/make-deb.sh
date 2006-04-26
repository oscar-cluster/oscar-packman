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

# we get the version number (first parameter)
number_of_args=$#
version_number=$1
path=`pwd`

echo "Be sure that we execute this script as root."
echo "Be also sure before to create the package that package information is up-to-date."
echo "Read the file deb/README for more details."
echo "Press enter to continue or Ctrl+C to abord."
read $toto

if [ $number_of_args -eq 0 ] 
then
  echo "You have to specify a version number as parameter. This number should be the same than in the deb/control file." 
else 

  echo "Creating Debian package for Packman/Depman version " $version_number

  # we first copy everything in /tmp/deb-packman and prepare a directory for packaging
  rm -rf /tmp/deb-packman
  mkdir -p /tmp/deb-packman/packman-depman-$version_number
  cp -rf ../* /tmp/deb-packman/packman-depman-$version_number
  rm -rf /tmp/deb-packman/packman-depman-$version_number/deb
  tar czf /tmp/deb-packman/packman-depman-$version_number.tar.gz /tmp/deb-packman/packman-depman-$version_number

  cd  /tmp/deb-packman/packman-depman-$version_number

  # we clean up the stub
  rm -f debian/*.ex debian/*.EX

  # we create all the files for the package
  dh_make -c gpl --single

  # a complete tree of directories is now ready. We update that thanks to information we already have.
  cd $path
  cp Makefile /tmp/deb-packman/packman-depman-$version_number
  cp debian/control /tmp/deb-packman/packman-depman-$version_number/debian
  cp debian/copyright /tmp/deb-packman/packman-depman-$version_number/debian
  
  # we then really create the package
  cd  /tmp/deb-packman/packman-depman-$version_number
  dpkg-buildpackage -rfakeroot

  # then we grab the created files :-)
  cd .. 
  cp -rf *.changes *.deb *.orig.tar.gz $path

  echo "Package(s) created and available in the deb directory"
fi

