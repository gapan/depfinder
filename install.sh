#!/bin/sh

install -d -m 755 $DESTDIR/usr/bin
install -d -m 755 $DESTDIR/usr/libexec
install -m 755 depfinder $DESTDIR/usr/bin/
install -m 755 depfinder-search/depfinder-search $DESTDIR/usr/libexec/

for i in `ls locale/*.mo`; do
                install -d -m 755 \
                $DESTDIR/usr/share/locale/`basename $i|sed "s/.mo//"`/LC_MESSAGES \
                2> /dev/null
                install -m 644 $i \
                $DESTDIR/usr/share/locale/`basename $i|sed "s/.mo//"`/LC_MESSAGES/depfinder.mo
done
