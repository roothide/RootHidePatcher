#!/bin/bash

set -e
shopt -s dotglob

LDID="ldid -Hsha256"
ECHO="echo -e"
FIND="find"
SED="sed"

if [ "$(sw_vers -productName)" == "macOS" ]; then
export TMPDIR=$(dirname "$1")
LOG() { $ECHO "$@\n"; }
SED="gsed"
FIND="gfind"
else
LOG() { return; }
#LOG() { $ECHO "$@\n"; }
export TMPDIR=/var/mobile/RootHidePatcher
fi

LOG "TMPDIR=$TMPDIR"

if [ $(whoami) != "root" ]; then
    $ECHO "Please run as root user (sudo)."
    exit 1;
fi

if ! type dpkg-deb >/dev/null 2>&1; then
	$ECHO "Please install dpkg-deb."
    exit 1;
fi

if ! type file >/dev/null 2>&1; then
	$ECHO "Please install file."
    exit 1;
fi

if ! type awk >/dev/null 2>&1; then
    $ECHO "Please install awk."
    exit 1;
fi

if ! ldid 2>&1 | grep -q procursus; then
	$ECHO "Please install Procursus ldid."
    exit 1;
fi


if [ -z "$1" ]; then
    $ECHO "Usage: $0 /path/to/deb [/path/to/output] [DynamicPatches|AutoPatches]"
    exit 1;
fi

if ! file "$1" | grep -q "Debian binary package" ; then
    $ECHO "*** Not a valid package!"
    exit 1;
fi

$ECHO "creating workspace..."
debfname=$(basename "$1")
TEMPDIR_OLD=$(mktemp -d "$TMPDIR/$debfname.old.XXXXXX")
TEMPDIR_NEW=$(mktemp -d "$TMPDIR/$debfname.new.XXXXXX")
chmod 0755 "$TEMPDIR_OLD" "$TEMPDIR_NEW"

if [ ! -d "$TEMPDIR_OLD" ] || [ ! -d "$TEMPDIR_NEW" ]; then
	$ECHO "*** Creating temporary directories failed!\n"
    exit 1;
fi

### Real script start

dpkg-deb -R "$1" "$TEMPDIR_OLD"

chmod -R 755 "$TEMPDIR_OLD"/DEBIAN
chmod 644 "$TEMPDIR_OLD"/DEBIAN/control

DEB_PACKAGE=$(grep '^Package:' "$TEMPDIR_OLD"/DEBIAN/control | cut -f2 -d ' ' | tr -d '\n\r')
DEB_VERSION=$(grep '^Version:' "$TEMPDIR_OLD"/DEBIAN/control | cut -f2 -d ' ' | tr -d '\n\r')
DEB_ARCH=$(grep '^Architecture:' "$TEMPDIR_OLD"/DEBIAN/control | cut -f2 -d ' ' | tr -d '\n\r')
DEB_MAINTAINER=$(grep '^Maintainer:' "$TEMPDIR_OLD"/DEBIAN/control | $SED -E 's/^Maintainer:\s*//' | tr -d '\n\r')

INCOMPATIBLE_PACKAGES=("xinam1ne" "xinamine" "legizmo" "vnodebypass" "voicechangerx-rootless" "appsyncunified" "choicy" "com.tigisoftware.filza" "sileo" "zebra" "com.opa334.ccsupport" "ws.hbang.common" "libsandy" "preferenceloader" "newterm3" "altlist")

# not tweaks
if [[ {ellekit,oldabi} =~ "$DEB_PACKAGE" ]] || [ "$DEB_MAINTAINER" == "Procursus Team <support@procurs.us>" ]; then
    $ECHO "*** Not a tweak package!\ncontact @RootHideDev to update it.\n\nskipping and exiting cleanly."
    rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
    exit 1;
else
    for substring in "${INCOMPATIBLE_PACKAGES[@]}"; do
      case "$DEB_PACKAGE" in
        *"$substring"*)
            $ECHO "*** This package is not compatible, please contact its developer to update it.\n\nskipping and exiting cleanly."
            rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
            exit 1;
          ;;
      esac
    done
fi

OUTPUT_PATH="$TMPDIR/$DEB_PACKAGE"_"$DEB_VERSION"_"iphoneos-arm64e".deb
if [ ! -z "$2" ]; then OUTPUT_PATH=$2; fi;

I_N_T() {
    if ! install_name_tool "$@" ; then
        ldid -s "${!#}"
        install_name_tool "$@"
        return $?
    fi
    return 0
}

exclude_files=(
    \! -path "*.lproj/*"
    \! -path "*.png"
    \! -path "*.gif"
    \! -path "*.jpg"
    \! -path "*.jpeg"
    \! -path "*.svg"
    \! -path "*.strings"
    \! -path "*.js"
    \! -path "*.py"
    \! -path "*.h"
    \! -path "*.json"
    \! -path "*.txt"
    \! -path "*.xml"
    \( \! -path "*.lua" -o -name "EQE.lua" \)
)

### Derootifier Script ##################################
Derootifier() {

    mv -f "$TEMPDIR_OLD"/* "$TEMPDIR_NEW"/
    
    findcmd=(find "$TEMPDIR_NEW" -type f -size +0c)
    for item in "${exclude_files[@]}"; do
        findcmd+=( $item )
    done

    "${findcmd[@]}" | while read -r file; do
      fname=$(basename "$file")
      fpath=/$(realpath --relative-base="$TEMPDIR_NEW" "$file")
      ftype=$(file -b "$file")
      if echo $ftype | grep -q "Mach-O"; then
        $ECHO "=> $fpath"
        $ECHO -n "patch..."
        otool -L "$file" | tail -n +2 | cut -d' ' -f1 | tr -d "[:blank:]" > "$TEMPDIR_OLD"/._lib_cache
        if [ -f "$TEMPDIR_OLD"/._lib_cache ]; then
            cat "$TEMPDIR_OLD"/._lib_cache | while read line; do
                if echo "$line" | grep -q ^/usr/lib/ ; then
                    I_N_T -change "$line" @rpath/"${line#/usr/lib/}" "$file"
                elif echo "$line" | grep -q ^/Library/Frameworks/ ; then
                    I_N_T -change "$line" @rpath/"${line#/Library/Frameworks/}" "$file"
                fi
            done
        fi
        I_N_T -add_rpath "/usr/lib" "$file"
        I_N_T -add_rpath "@loader_path/.jbroot/usr/lib" "$file"
        I_N_T -add_rpath "/Library/Frameworks" "$file" >/dev/null
        I_N_T -add_rpath "@loader_path/.jbroot/Library/Frameworks" "$file"

        $ECHO -n "resign..."
        if echo $ftype | grep -q "executable"; then
            $LDID -M "-S$(dirname $(realpath $0))/roothide.entitlements" "$file"
        else
            $LDID -S "$file"
        fi
        $ECHO "~ok."
      fi
    done
    
    
    $SED -i '/^$/d' "$TEMPDIR_NEW"/DEBIAN/control
    $SED -i 's|iphoneos-arm|iphoneos-arm64e|g' "$TEMPDIR_NEW"/DEBIAN/control


    find "$TEMPDIR_NEW" -name ".DS_Store" -delete
    dpkg-deb -Zzstd -b "$TEMPDIR_NEW" "$OUTPUT_PATH"
    chown 501:501 "$OUTPUT_PATH"

    ### Real script end

    $ECHO "\nfinished. cleaning up..."

    if [ "$(sw_vers -productName)" != "macOS" ]; then
        rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
        rm -f $1
    fi

}
####################################################################

if [ $DEB_ARCH == "iphoneos-arm" ] && [ -z "$3" ]; then
    Derootifier $@
    exit 0
elif [ $DEB_ARCH == "iphoneos-arm" ]; then
    $ECHO "$DEB_ARCH\n*** It's a rootful package, you can try the first option [Directly Convert Simple Tweaks]\n\nskipping and exiting cleanly."
    rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
    exit 1;
elif [ $DEB_ARCH != "iphoneos-arm64" ]; then
    $ECHO "$DEB_ARCH\n*** Not a rootless package!\n\nskipping and exiting cleanly."
    rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
    exit 1;
fi

mv -f "$TEMPDIR_OLD"/DEBIAN "$TEMPDIR_NEW"/

#dpkg-deb -c "$1" > "$TEMPDIR_NEW"/DEBIAN/list
#$SED -i -E 's|^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+||g' "$TEMPDIR_NEW"/DEBIAN/list
#$SED -i -E 's|^(\.\/)?|/|g' "$TEMPDIR_NEW"/DEBIAN/list
#$SED -i -E '1s|^\/$|/.|'  "$TEMPDIR_NEW"/DEBIAN/list
#
#if [ ! -e "$TEMPDIR_NEW"/DEBIAN/md5sums ]; then
#    cd "$TEMPDIR_OLD"
#    eval md5sum $($FIND "$TEMPDIR_OLD" -type f -printf "\"%P\"\n") > "$TEMPDIR_NEW"/DEBIAN/md5sums  #E2BIG on ios
#    cd -
#fi

if [ -d "$TEMPDIR_OLD/var/jb" ]; then
    subitemcount=$(ls -A "$TEMPDIR_OLD/var/jb")
    if [ -n "$subitemcount" ]; then mv -f "$TEMPDIR_OLD"/var/jb/* "$TEMPDIR_NEW"/ ; fi
    rmdir "$TEMPDIR_OLD"/var/jb
fi
rmdir "$TEMPDIR_OLD"/var >/dev/null 2>&1 || true
rootfsfiles=$(ls "$TEMPDIR_OLD")
if [ ! -z "$rootfsfiles" ]; then
    mkdir "$TEMPDIR_NEW"/rootfs
    mv -f "$TEMPDIR_OLD"/* "$TEMPDIR_NEW"/rootfs/
fi
# some packages have both /var/jb/var/xxx and /var/xxx, same file same name
if [ ! -z "$3" ]; then
    mkdir -p "$TEMPDIR_OLD"/pkgmirror
    cp -a "$TEMPDIR_NEW"/. "$TEMPDIR_OLD"/pkgmirror/
    mv "$TEMPDIR_OLD"/pkgmirror/DEBIAN "$TEMPDIR_OLD"/pkgmirror/DEBIAN.$DEB_PACKAGE
    mkdir -p "$TEMPDIR_NEW"/var/mobile/Library
    mv "$TEMPDIR_OLD"/pkgmirror "$TEMPDIR_NEW"/var/mobile/Library/
# append after "Package" : "Status: install ok installed" > "$TEMPDIR_NEW"/var/mobile/Library/pkgmirror/DEBIAN.$DEB_PACKAGE/control
fi

#rm -f "$TEMPDIR_NEW"/DEBIAN/list "$TEMPDIR_NEW"/DEBIAN/md5sums

# List LC_RPATH entries, optionally for one architecture.
lsrpath() {
    if [ "$1" = "-arch" ]; then
        otool -arch "$2" -l "$3"
    else
        otool -l "$@"
    fi |
    awk '
        /^[^ ]/ {f = 0}
        $2 == "LC_RPATH" && $1 == "cmd" {f = 1}
        f && gsub(/^ *path | \(offset [0-9]+\)$/, "") == 2
    ' | sort | uniq
}

# True if path exists in every architecture slice of the file.
rpath_in_all_archs() {
    local file=$1 path=$2 arch archs
    archs=$(otool -l "$file" | $SED -n 's/.*(architecture \([^)]*\)).*/\1/p' | sort | uniq)
    if [ -z "$archs" ]; then
        lsrpath "$file" | grep -Fqx "$path"
        return
    fi
    for arch in $archs; do
        lsrpath -arch "$arch" "$file" | grep -Fqx "$path" || return 1
    done
    return 0
}

findcmd=(find "$TEMPDIR_NEW" -type f -size +0c \! -path "*/var/mobile/Library/pkgmirror/*")
for item in "${exclude_files[@]}"; do
    findcmd+=( $item )
done

"${findcmd[@]}" | while read -r file; do
  LOG "$file"
  fixedpaths=""
  fname=$(basename "$file")
  fpath=/$(realpath --relative-base="$TEMPDIR_NEW" "$file")
  ftype=$(file -b "$file")
  if echo $ftype | grep -q "Mach-O"; then
    $ECHO "=> $fpath"
    $ECHO -n "patch..."
    lsrpath "$file" | while read -r line; do
        if [[ $line == /var/jb/* ]]; then
            newpath=${line/\/var\/jb\//@loader_path\/.jbroot\/}
            # -rpath doesn't check the destination. Delete the dead /var/jb
            # entry when .jbroot is already present in every slice.
            if rpath_in_all_archs "$file" "$newpath"; then
                I_N_T -delete_rpath "$line" "$file"
                LOG "delete rpath" "$line"
            else
                I_N_T -rpath "$line" "$newpath" "$file"
                LOG "change rpath" "$line" "$newpath"
            fi
        fi
    done
    otool -L "$file" | tail -n +2 | cut -d' ' -f1 | tr -d "[:blank:]" | while read line; do
        if [[ $line == /var/jb/* ]]; then
            newlib=${line/\/var\/jb\//@loader_path\/.jbroot\/}
            LOG "change library" "$line" "$newlib"
            I_N_T -change "$line" "$newlib" "$file"
        fi
    done
    $ECHO -n "resign..."
    if echo $ftype | grep -q "executable"; then
        $LDID -M "-S$(dirname $(realpath $0))/roothide.entitlements" "$file"
    else
        $LDID -S "$file"
    fi
    $ECHO "~ok."
    fixedpaths=$(strings - "$file" | grep /var/jb || true)
    if [ "$3" == "AutoPatches" ]; then
        ln -s /usr/lib/DynamicPatches/AutoPatches.dylib "$file".roothidepatch
    fi
  elif ! [[ {png,strings} =~ "${fname##*.}" ]]; then
    if [[ {preinst,prerm,postinst,postrm,extrainst_} =~ "$fname" ]]; then
        $SED -i 's|iphoneos-arm64|iphoneos-arm64e|g' "$file"
                        
        $SED -i 's|/var/jb/|/-var/jb/-|g' "$file"
        $SED -i 's|/var/jb|/-var/jb-|g' "$file"
        
        $SED -i 's| /Applications/| /rootfs/Applications/|g' "$file"
        $SED -i 's| /Library/| /rootfs/Library/|g' "$file"
        $SED -i 's| /private/| /rootfs/private/|g' "$file"
        $SED -i 's| /System/| /rootfs/System/|g' "$file"
        $SED -i 's| /sbin/| /rootfs/sbin/|g' "$file"
        $SED -i 's| /bin/| /rootfs/bin/|g' "$file"
        $SED -i 's| /etc/| /rootfs/etc/|g' "$file"
        $SED -i 's| /lib/| /rootfs/lib/|g' "$file"
        $SED -i 's| /usr/| /rootfs/usr/|g' "$file"
        $SED -i 's| /var/| /rootfs/var/|g' "$file"
                
        $SED -i 's|DIR="/Library/|DIR="/rootfs/Library/|g' "$file"
        
        $SED -i '1s|^#!\s*\/rootfs\/|#! \/|' "$file"  #revert shebang
                                                
        $SED -i 's|/-var/jb/-|/|g' "$file"
        $SED -i 's|/-var/jb-|/var/jb|g' "$file"
    fi
    if [ "${fname##*.}" == "plist" ]; then
        plutil -convert xml1 "$file" >/dev/null
        if [[ {/Library/LaunchDaemons} =~ $(dirname "$fpath") ]]; then
            $SED -i 's|/var/jb/|/|g' "$file"
        elif [[ {/Library/libSandy} =~ $(dirname "$fpath") ]]; then
            $SED -i 's|/var/jb/|/-var/jb/-|g' "$file"
            $SED -i 's|/var/jb|/-var/jb-|g' "$file"
                    
            $SED -i 's|>/<|>/rootfs/<|g' "$file"
            $SED -i 's|>/Applications/|>/rootfs/Applications/|g' "$file"
            $SED -i 's|>/Library/|>/rootfs/Library/|g' "$file"
            $SED -i 's|>/private/|>/rootfs/private/|g' "$file"
            $SED -i 's|>/System/|>/rootfs/System/|g' "$file"
            $SED -i 's|>/sbin/|>/rootfs/sbin/|g' "$file"
            $SED -i 's|>/bin/|>/rootfs/bin/|g' "$file"
            $SED -i 's|>/etc/|>/rootfs/etc/|g' "$file"
            $SED -i 's|>/lib/|>/rootfs/lib/|g' "$file"
            $SED -i 's|>/usr/|>/rootfs/usr/|g' "$file"
            $SED -i 's|>/var/|>/rootfs/var/|g' "$file"
            
            $SED -i 's|/-var/jb/-|/|g' "$file"
            $SED -i 's|/-var/jb-|/var/jb|g' "$file"
        fi
    fi
    fixedpaths=$(strings - "$file" | grep /var/jb || true)
    if [ ! -z "$fixedpaths" ]; then
        $ECHO "=> $fpath"
    fi
  fi
  if [ ! -z "$fixedpaths" ]; then
    $ECHO "*****fixed-paths-warnning*****\n$fixedpaths\n*******************************\n"
  fi
done

    
if [ ! -z "$3" ]; then
    cp "$TEMPDIR_NEW"/DEBIAN/*.roothidepatch "$TEMPDIR_NEW"/var/mobile/Library/pkgmirror/DEBIAN.$DEB_PACKAGE/ >/dev/null 2>&1 || true
    chown -R 501:501 "$TEMPDIR_NEW"/var/mobile/Library/pkgmirror/
    chmod -R 0755 "$TEMPDIR_NEW"/var/mobile/Library/pkgmirror/
fi

$SED -i '/^$/d' "$TEMPDIR_NEW"/DEBIAN/control
$SED -i 's|iphoneos-arm64|iphoneos-arm64e|g' "$TEMPDIR_NEW"/DEBIAN/control
$SED -i '/^Conflicts: /s/roothide/r-o-o-t-l-e-s-s-/g' "$TEMPDIR_NEW"/DEBIAN/control

if [ "$3" == "AutoPatches" ]; then
    PreDepends="rootless-compat(>= 0.9)"
elif [ "$3" == "DynamicPatches" ]; then
    $SED -i "/^Version\:/d" "$TEMPDIR_NEW"/DEBIAN/control
    echo "Version: $DEB_VERSION~roothide" >> "$TEMPDIR_NEW"/DEBIAN/control
    PreDepends="patches-$DEB_PACKAGE(= $DEB_VERSION~roothide)"
fi

if [ "$PreDepends" != "" ]; then
    if grep -q '^Pre-Depends:' "$TEMPDIR_NEW"/DEBIAN/control; then
        $SED -i "s/^Pre-Depends\:/Pre-Depends: $PreDepends,/" "$TEMPDIR_NEW"/DEBIAN/control
    else
        echo "Pre-Depends: $PreDepends" >> "$TEMPDIR_NEW"/DEBIAN/control
    fi
fi


find "$TEMPDIR_NEW" -name ".DS_Store" -delete
dpkg-deb -Zzstd -b "$TEMPDIR_NEW" "$OUTPUT_PATH"
chown 501:501 "$OUTPUT_PATH"

### Real script end

$ECHO "\nfinished. cleaning up..."

if [ "$(sw_vers -productName)" != "macOS" ]; then
    rm -rf "$TEMPDIR_OLD" "$TEMPDIR_NEW"
    rm -f $1
fi

