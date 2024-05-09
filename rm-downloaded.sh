#!/bin/sh
cd "${0%/*}"
ARCHES="armv7 aarch64 x86 x86_64"
echo "This will REMOVE ALL APK FILES in the following directories:"
# echo "    $ARCHES"
for ARCH in $ARCHES; do
    echo "    $PWD/$ARCH"
done
read -r -p "Proceed (y/N)? " CHOICE
case "$CHOICE" in
    y|Y)
        for ARCH in $ARCHES; do
            rm $ARCH/*.apk
        done
        ;;
    *)  echo "Exiting without removing";;
esac
exit 0
