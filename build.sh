#!/bin/bash

export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1
# NO_SYS_MUSL=1

kmod_version="latest"
musl_version="latest"

platform="$(uname -s)"
platform_arch="$(uname -m)"

[ "$kmod_version" == "latest" ] && \
  kmod_version="$(curl -s https://github.com/kmod-project/kmod/releases|\
                  grep -Eo "/tag.*[0-9]\""|sed 's|/tag/||g;s|"||g;s|v||g'|head -1)"

[ "$musl_version" == "latest" ] && \
  musl_version="$(curl -s https://www.musl-libc.org/releases/|tac|grep -v 'latest'|\
                  grep -om1 'musl-.*\.tar\.gz'|cut -d'>' -f2|sed 's|musl-||g;s|.tar.gz||g')"

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [ -d release ]
    then
        echo "= removing previous release directory"
        rm -rf release
fi

# create build and release directory
mkdir build
mkdir release
pushd build

# download tarballs
echo "= downloading kmod v${kmod_version}"
git clone https://github.com/kmod-project/kmod.git kmod-${kmod_version}

if [ "$platform" == "Linux" ]
    then
        echo "= setting CC to musl-gcc"
        if [[ ! -x "$(which musl-gcc 2>/dev/null)" || "$NO_SYS_MUSL" == 1 ]]
            then
                echo "= downloading musl v${musl_version}"
                curl -LO https://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

                echo "= extracting musl"
                tar -xf musl-${musl_version}.tar.gz

                echo "= building musl"
                working_dir="$(pwd)"

                install_dir="${working_dir}/musl-install"

                pushd musl-${musl_version}
                env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" LDFLAGS='-Wl,--gc-sections' ./configure --prefix="${install_dir}"
                make install
                popd # musl-${musl-version}
                export CC="${working_dir}/musl-install/bin/musl-gcc"
            else
                export CC="$(which musl-gcc 2>/dev/null)"
        fi
        NEWCFLAGS="-static"
        NEWLDFLAGS='-all-static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building kmod"
pushd kmod-${kmod_version}
CFLAGS="$NEWCFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" ./autogen.sh
./configure CC="$CC" CFLAGS="$NEWCFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" LDFLAGS="$NEWCFLAGS -Wl,--gc-sections"
CFLAGS="$NEWCFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" make LDFLAGS="$NEWLDFLAGS -Wl,--gc-sections"
popd # kmod-${kmod_version}

popd # build

shopt -s extglob

echo "= extracting kmod binary"
for file in {depmod,insmod,kmod,lsmod,modinfo,modprobe,rmmod}
    do
        mv "build/kmod-${kmod_version}/tools/$file" release 2>/dev/null
done

echo "= striptease"
for file in release/*
  do
      strip -s -R .comment -R .gnu.version --strip-unneeded "$file" 2>/dev/null
done

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        for file in release/*
          do
              upx -9 --best "$file" 2>/dev/null
        done
fi

echo "= create release tar.xz"
tar --xz -acf kmod-static-v${kmod_version}-${platform_arch}.tar.xz release

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= kmod v${kmod_version} done"
