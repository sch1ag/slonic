#!/bin/bash

if ! uname -a | egrep 'SunOS.*5\.11.*' > /dev/null ; then
  echo "This script could run only on Solaris 11"
  exit 1
fi

BUILD_TMP=pkgbuild_tmp
PROTO=$BUILD_TMP/sunos11_proto
PKGNAME=slonic
PKG_VERS=`cat VERSION`
MOG_FILE=sunos11_slonic.mog
MOG_FILE_DEP=sunos11_slonic.mog.dep
PUBLISHER=slonic-publisher
REPONAME=slonic-repo

rm $BUILD_TMP/${PKGNAME}.p5m.*
pkgsend generate $PROTO | pkgfmt > $BUILD_TMP/${PKGNAME}.p5m.1
pkgmogrify -D PKG_VERS=$PKG_VERS $BUILD_TMP/${PKGNAME}.p5m.1 $MOG_FILE | pkgfmt > $BUILD_TMP/${PKGNAME}.p5m.2
pkgdepend generate -md $PROTO $BUILD_TMP/${PKGNAME}.p5m.2 | pkgfmt > $BUILD_TMP/${PKGNAME}.p5m.3
pkgdepend resolve -m $BUILD_TMP/${PKGNAME}.p5m.3
pkgmogrify $BUILD_TMP/${PKGNAME}.p5m.3.res $MOG_FILE_DEP | pkgfmt > $BUILD_TMP/${PKGNAME}.p5m.4.res
[ -f $BUILD_TMP/${REPONAME}/pkg5.repository ] || pkgrepo create $BUILD_TMP/${REPONAME}
pkgrepo -s $BUILD_TMP/${REPONAME} set publisher/prefix=$PUBLISHER
pkgsend -s $BUILD_TMP/${REPONAME} publish -d $PROTO $BUILD_TMP/${PKGNAME}.p5m.4.res
pkgrepo -s $BUILD_TMP/${REPONAME} info
[ -f ${PKGNAME}.${PKG_VERS}.p5p ] && rm ${PKGNAME}.${PKG_VERS}.p5p
pkgrecv -s ${BUILD_TMP}/${REPONAME}/ -a -d ${PKGNAME}.${PKG_VERS}.p5p ${PKGNAME}
