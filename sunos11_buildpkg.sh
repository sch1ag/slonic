#!/bin/bash

if ! uname -a | egrep 'SunOS.*5\.11.*' > /dev/null ; then
  echo "This script could run only on Solaris 11"
  exit 1
fi


BUILD_TMP=pkgbuild_tmp
PROTO=$BUILD_TMP/sunos11_proto
SLONIC_VERS=`cat VERSION`
MOG_FILE=sunos11_slonic.mog

rm $BUILD_TMP/slonic.p5m.*
pkgsend generate $PROTO | pkgfmt > $BUILD_TMP/slonic.p5m.1
pkgmogrify -D SLONIC_VERS=$SLONIC_VERS $BUILD_TMP/slonic.p5m.1 $MOG_FILE | pkgfmt > $BUILD_TMP/slonic.p5m.2
pkgdepend generate -md $PROTO $BUILD_TMP/slonic.p5m.2 | pkgfmt > $BUILD_TMP/slonic.p5m.3
pkgdepend resolve -m $BUILD_TMP/slonic.p5m.3
[ -f $BUILD_TMP/slonic-repo/pkg5.repository ] || pkgrepo create $BUILD_TMP/slonic-repo
pkgrepo -s $BUILD_TMP/slonic-repo set publisher/prefix=slonic-publisher
pkgsend -s $BUILD_TMP/slonic-repo publish -d $PROTO $BUILD_TMP/slonic.p5m.3.res
pkgrepo -s $BUILD_TMP/slonic-repo info
[ -f slonic.p5p ] && rm slonic.p5p
pkgrecv -s $BUILD_TMP/slonic-repo/ -a -d slonic.p5p slonic
