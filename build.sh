#!/bin/bash

export BUILDER_BASE_DIR="${BUILDER_BASE_DIR:-$PWD}"
export BUILDER_TA_LIB_DIR="${BUILDER_TA_LIB_DIR:-${BUILDER_BASE_DIR}/ta-lib}"
export BUILDER_DEBIAN_DIR="${BUILDER_DEBIAN_DIR:-${BUILDER_BASE_DIR}/debian}"

echo "- Updating package lists"
sudo apt-get update || { echo "- Failed to update package lists"; exit 1; }

echo "- Installing dependencies"
sudo apt-get install -y autoconf libtool make automake git build-essential debhelper wget jq curl fakeroot || { echo "- Failed to install dependencies"; exit 1; }

echo "- Creating build directories"
mkdir -p "${BUILDER_DEBIAN_DIR}/tmp/usr/lib"
mkdir -p "${BUILDER_DEBIAN_DIR}/tmp/usr/pkgconfig"
mkdir -p "${BUILDER_DEBIAN_DIR}/tmp/usr/include"
mkdir -p "${BUILDER_DEBIAN_DIR}/debian"
mkdir -p "${BUILDER_DEBIAN_DIR}/debian/source"
mkdir -p "${BUILDER_BASE_DIR}/output"

echo "- Cloning TA-Lib repository"
if [ ! -d "${BUILDER_TA_LIB_DIR}/.git" ]; then
    rm -rf "${BUILDER_TA_LIB_DIR}"
    git clone https://github.com/TA-Lib/ta-lib.git "${BUILDER_TA_LIB_DIR}"
else
    git -C "${BUILDER_TA_LIB_DIR}" fetch
    git -C "${BUILDER_TA_LIB_DIR}" reset --hard origin/master
    git -C "${BUILDER_TA_LIB_DIR}" clean -fdx
fi
cd "${BUILDER_TA_LIB_DIR}"

echo "- Cleaning up configuration artifacts"
if [ -f Makefile ]; then
    make distclean || echo "- Manual cleanup required"
fi
find . -name 'config.status' -delete
find . -name 'config.cache' -delete
find . -name 'Makefile' -delete

echo "- Updating configuration scripts"
curl -o config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' || { echo "- Failed to download config.guess"; exit 1; }
curl -o config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' || { echo "- Failed to download config.sub"; exit 1; }

echo "- Running autogen.sh"
chmod +x ./autogen.sh
./autogen.sh

echo "- Running configure"
./configure --prefix=/usr --verbose

echo "- Running make"
make
make install DESTDIR="${BUILDER_DEBIAN_DIR}/tmp"

echo "- Copying library files to the correct location"
mkdir -p "${BUILDER_DEBIAN_DIR}/usr/lib"
cp -R "${BUILDER_DEBIAN_DIR}/tmp/usr/"* "${BUILDER_DEBIAN_DIR}/usr/"

echo "- Creating release files"
cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/ta-lib.install"
usr/lib/libta_lib.so.0.0.0
usr/lib/libta_lib.so.0
usr/lib/libta_lib.so
usr/include/ta-lib/*.h
usr/lib/libta_lib.a
usr/lib/pkgconfig/ta-lib.pc
EOF

cp -f README.md "${BUILDER_DEBIAN_DIR}/debian/"

cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/control"
Source: ta-lib
Section: libs
Priority: optional
Maintainer: lnxd <48756329+lnxd@users.noreply.github.com>
Build-Depends: debhelper (>= 9), autoconf, libtool, make, automake, git, build-essential, wget, jq, curl
Standards-Version: 4.5.1
Homepage: https://github.com/TA-Lib/ta-lib

Package: ta-lib
Architecture: any
Depends: libc6, ${misc:Depends}
Description: TA-Lib provides common functions for the technical analysis of stock/future/commodity market data.
EOF

cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/rules"
#!/usr/bin/make -f
%:
	dh \$@

override_dh_auto_configure:
	dh_auto_configure -- --prefix=/usr

override_dh_auto_build:
	dh_auto_build

override_dh_auto_install:
	dh_auto_install

override_dh_makeshlibs:
	dh_makeshlibs -V
EOF

chmod +x "${BUILDER_DEBIAN_DIR}/debian/rules"

cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/compat"
10
EOF

cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/source/format"
3.0 (quilt)
EOF

if [ -f "${BUILDER_TA_LIB_DIR}/LICENSE" ] || [ -f "${BUILDER_TA_LIB_DIR}/license" ]; then
    find "${BUILDER_TA_LIB_DIR}" -maxdepth 1 -type f -iname "license*" -exec cp {} "${BUILDER_DEBIAN_DIR}/debian/copyright" \;
else # License sourced from ta-lib-0.4.0-msvc.zip 
    cat << EOF > "${BUILDER_DEBIAN_DIR}/debian/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ta-lib
Source: https://github.com/TA-Lib/ta-lib

TA-Lib Copyright (c) 1999-2007, Mario Fortier
All rights reserved.

Redistribution and use in source and binary forms, with or
without modification, are permitted provided that the following
conditions are met:

- Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in
  the documentation and/or other materials provided with the
  distribution.

- Neither name of author nor the names of its contributors
  may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
EOF
fi

UPSTREAM_VERSION="0.4.0"
UNIX_EPOCH=$(date +%s)
NEW_VERSION="${UPSTREAM_VERSION}-dev${UNIX_EPOCH}-1"

cat <<EOL > "${BUILDER_DEBIAN_DIR}/debian/changelog"
ta-lib (${NEW_VERSION}) unstable; urgency=low

  * Please check commit history at https://github.com/TA-Lib/ta-lib/commits/main/

 -- lnxd <48756329+lnxd@users.noreply.github.com>  $(date -R)
EOL

echo "- Build ready. Output files are in ${BUILDER_DEBIAN_DIR}"

echo "- Building the package"
cd "${BUILDER_DEBIAN_DIR}"
dpkg-buildpackage -us -uc -b

echo "- Moving .deb file to output directory"
mv ../*.deb "${BUILDER_BASE_DIR}/output/"
mv *.buildinfo "${BUILDER_BASE_DIR}/output/"

echo "- Debian package built and moved to ${BUILDER_BASE_DIR}/output/"
ls -lha ${BUILDER_BASE_DIR}/output/