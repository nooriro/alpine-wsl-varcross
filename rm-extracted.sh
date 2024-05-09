#!/bin/sh
cd "${0%/*}"
ARCHES="armv7 aarch64 x86 x86_64"
for ARCH in $ARCHES; do
    # rm `-f` suppresses non-existence error message
    # See https://stackoverflow.com/a/10250395
    rm -rf $ARCH/*/
    rm -f $ARCH/.PKGINFO
    rm -f $ARCH/.SIGN.RSA.alpine-devel@lists.alpinelinux.org-????????.rsa.pub
done
exit 0
