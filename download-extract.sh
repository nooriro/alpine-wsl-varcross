#!/bin/sh
cd "${0%/*}"

ARCHES="armv7 aarch64 x86 x86_64"
# PKGS="musl-dev compiler-rt"
PKGS="musl-dev compiler-rt libc++-dev libc++-static
      llvm-libunwind-dev llvm-libunwind-static gcc"

get_prop() {
    local VALUE="$(sed -nE "s/^$1=\"(.*)\"[ \t]*$/\1/p" "$2" | head -n 1)"
    [ -z "$VALUE" ] && VALUE="$(sed -n "s/^$1=//p" "$2" | head -n 1)"
    printf '%s\n' "$VALUE"
}

get_os_release() {
    get_prop "$1" /etc/os-release
}

# $1=MONTHNAME (Jan, Feb, Mar, ..., Dec)
monthnum() {
    local MONTHNAMES="Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec "
    local FOO="${MONTHNAMES%$1*}"
    echo "$((${#FOO}/4+1))"
}

# $1=YEAR  $2=MONTH  $3=DAY  $4=HOUR  $5=MINUTE  $6=SECOND
# only works for positive years, since `/` and `%` in `(( ))` perform truncated division
unixtime() {
    local DBY="$(( (10#$1-1970)*365 + (10#$1-1)/4 - (10#$1-1)/100 + (10#$1-1)/400 - 477 ))"
    local DBM="   0  31  59  90 120 151 181 212 243 273 304 334"
    DBM="$(echo ${DBM:$(((10#$2-1)*4)):4})"
    if [ $2 -gt 2 ] && { [ $(($1%4)) -eq 0 ] && [ $(($1%100)) -ne 0 ] || [ $(($1%400)) -eq 0 ]; }; then
        DBM="$(($DBM+1))"
    fi
    local DBD="$((10#$3-1))"
    echo "$(( ($DBY+$DBM+$DBD)*86400 + 10#$4*3600 + 10#$5*60 + 10#$6 ))"
}

# $1=DATESTRING (example: "Mon, 06 Nov 2023 12:23:51 GMT")
unixtime2() {
    local YEAR="${1:12:4}"
    local MONTH="$(monthnum "${1:8:3}")"
    local DAY="${1:5:2}"
    local HOUR="${1:17:2}"
    local MINUTE="${1:20:2}"
    local SECOND="${1:23:2}"
    # echo "|$YEAR|$MONTH|$DAY|$HOUR|$MINUTE|$SECOND|"
    unixtime "$YEAR" "$MONTH" "$DAY" "$HOUR" "$MINUTE" "$SECOND"
}

# Use {} with && and || for C-style if block: see https://stackoverflow.com/a/41308634
# rm `-f` suppresses non-existence error message: see https://stackoverflow.com/a/10250395

# Check if Alpine
echo "NAME:          $(get_os_release NAME)"
echo "VERSION_ID:    $(get_os_release VERSION_ID)"
echo "PRETTY_NAME:   $(get_os_release PRETTY_NAME)"
ALPINE="$(cat /etc/alpine-release 2>/dev/null)"
if [ -z "$ALPINE" ]; then
    echo "error: this OS is not Alpine Linux" 1>&2
    exit 1
fi

# Detect $REPO
REPO="$(cat /etc/apk/repositories | grep '^http.*main$' | head -n 1)"
if [ -z "$REPO" ]; then
    echo "error: no main repository in /etc/apk/repositories" 1>&2
    exit 1
fi
echo "Repository:    $REPO"
echo "Architecture:  $(echo $ARCHES)"

# Count and print packages
NUM_PKGS="0"
for PKG in $PKGS; do
    NUM_PKGS=$((NUM_PKGS+1))
done
i="0"
echo "Packages:"
for PKG in $PKGS; do
    i=$((i+1))
    ORD="($i/$NUM_PKGS)"
    printf '%14s %s\n' $ORD $PKG
done

# Make sure every $ARCH dir exists
for ARCH in $ARCHES; do
    if [ ! -d $ARCH ]; then
        if [ -e $ARCH ]; then
            echo "error: $ARCH exists in ${0%/*} but is not a directory" 1>&2
            exit 1
        fi
        mkdir $ARCH
    fi
done

# Collect APK filenames from $REPO
APKS=""
NOTS=""
i="0"
echo "APK filenames:"
for PKG in $PKGS; do
    i=$((i+1))
    ORD="($i/$NUM_PKGS)"
    APK="$(apk list --from none --repository $REPO $PKG | sed -n "s/ .*//p").apk"
    printf '%14s %s\n' $ORD $APK
    [ "$APK" != ".apk" ] && APKS="$APKS $APK" || NOTS="$NOTS $PKG"
done
APKS="${APKS:1}"
NOTS="${NOTS:1}"
if [ -n "$NOTS" ]; then
    echo "error: some packages do not exist in repo: $NOTS" 1>&2
    exit 1
fi

# Test existing APK files
FOUND="0"
for ARCH in $ARCHES; do
    for APK in $APKS; do
        [ -f "$ARCH/$APK" ] && FOUND=$((FOUND+1))
    done
done
echo -n "Testing downloaded $FOUND APK file(s)..."
OK="0"
NUM_DL="0"
for ARCH in $ARCHES; do
    for APK in $APKS; do
        if [ -f "$ARCH/$APK" ]; then
            gzip -t "$ARCH/$APK" 2>/dev/null && { OK=$((OK+1)); continue; }
        fi
        # Remove corrupted file
        # '-f' suppresses non-existence error message
        rm -f "$ARCH/$APK"
        NUM_DL=$((NUM_DL+1))
    done
done
echo " $OK file(s) are OK"
[ $NUM_DL -gt 0 ] && echo "Downloading $NUM_DL file(s)" || echo "No files to download"

# Download packages
i="0"
for ARCH in $ARCHES; do
    for APK in $APKS; do
        [ -f "$ARCH/$APK" ] && continue
        i="$((i+1))"
        URL="$REPO/$ARCH/$APK"
        echo "($i/$NUM_DL) $URL"
        RETRY="0"
        while true; do
            wget -c -P $ARCH "$URL" 2>&1 | while read -r LINE; do
                case "$LINE" in
                    *%*)
                        LINE="${LINE}  (RETRY=$RETRY)"
                        [ -t 1 ] && FMT="%s\r" || FMT="%s\n"
                        printf "$FMT" "$LINE"
                        ;;
                esac
            done
            # Mimic APK's behavior: preserve last modified time from server
            DATESTR="$(wget --spider -S "$URL" 2>&1 | sed -n 's/^  Last-Modified: //p')"
            DATESTR2="$(date -d @$(unixtime2 "$DATESTR") +'%Y-%m-%d %H:%M:%S')"
            touch -d "$DATESTR2" "$ARCH/$APK"
            gzip -t "$ARCH/$APK" 2>/dev/null && break
            RETRY="$((RETRY+1))"
            if [ $RETRY -eq 10 ]; then
                [ -t 1 ] && echo
                echo "error: download failed" 1>&2
                exit 1
            fi
        done
        [ -t 1 ] && printf "%91s\r" " " 
    done
done

# Extract packages
RET="0"
for ARCH in $ARCHES; do
    for APK in $APKS; do
        echo -n "Extracting $ARCH/$APK"
        if [ "${APK:0:4}" = "gcc-" ]; then
            echo -n " (only 'libgcc.a')"
            LIST0="$(tar tzf "$ARCH/$APK" 2>/dev/null | grep '^usr/lib/gcc/[^/]\+/[^/]\+/libgcc.a$')"
            [ -n "$LIST0" ] || { echo "  [FAILED]"; RET="1"; continue; }
        else
            LIST0=""  # Extract all files
        fi
        tar xzpf "$ARCH/$APK" $LIST0 -C "$ARCH" 2>/dev/null && echo || { echo "  [FAILED]"; RET="1"; }
    done
    rm -f $ARCH/.PKGINFO
    rm -f $ARCH/.SIGN.RSA.alpine-devel@lists.alpinelinux.org-????????.rsa.pub
done

exit $RET
