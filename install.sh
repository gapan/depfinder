#!/bin/sh

if [ "$1" == "-64" ];then
	export CXXFLAGS=${CXXFLAGS:="-O3 -fPIC -fomit-frame-pointer"}
else
	export CXXFLAGS=${CXXFLAGS:="-O3 -march=i486 -mtune=i686 -fomit-frame-pointer"}
fi

( cd depfinder-search && ./compile )
	
install -d -m 755 $DESTDIR/usr/bin
install -d -m 755 $DESTDIR/usr/libexec
install -m 755 depfinder $DESTDIR/usr/bin/
install -m 755 depfinder-search/depfinder-search $DESTDIR/usr/libexec/

if [ "$1" == "-64" ];then
	sed -i "s/^LIBDIRSUFFIX=.*/LIBDIRSUFFIX=\"64\"/" $DESTDIR/usr/bin/depfinder
fi

