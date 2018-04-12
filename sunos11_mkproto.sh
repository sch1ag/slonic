BUILD_TMP=pkgbuild_tmp
DESTDIR=$BUILD_TMP/sunos11_proto
rm -rf $DESTDIR

mkdir -p $DESTDIR

PROTO_MKDIRS="opt/slonic etc/init.d etc/default etc/opt/slonic/slonic.chief.orders"
for NEWDIR in $PROTO_MKDIRS; do
  mkdir -p $DESTDIR/$NEWDIR
done

cp extra/init.d/slonic $DESTDIR/etc/init.d/
cp extra/default/slonic $DESTDIR/etc/default/

PROTO_CPDIRS="bin lib etc"
for CPDIR in $PROTO_CPDIRS; do
  cp -r $CPDIR $DESTDIR/opt/slonic
done

cp extra/etc_samples/*.json $DESTDIR/etc/opt/slonic

exit 0
