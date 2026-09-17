#!/usr/bin/env bash
# Build OpenSSL + libcurl + curl.exe with MinGW-w64 (MSYS2).
# Usage:
#   ./scripts/build-mingw.sh static x64 [/path/out]
#   ./scripts/build-mingw.sh shared x86 [/path/out]
set -euo pipefail

LINK_TYPE="${1:-static}"
ARCH="${2:-x64}"
OUT_DIR="${3:-}"
CURL_VERSION="${CURL_VERSION:-8.11.1}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/build/mingw-${ARCH}-${LINK_TYPE}"
SRC="${WORK}/src"
STAGE="${WORK}/stage"

if [[ "${ARCH}" == "x64" ]]; then
  OPENSSL_TARGET="mingw64"
  MINGW_PREFIX="/mingw64"
  RC_TARGET="pe-x86-64"
elif [[ "${ARCH}" == "x86" ]]; then
  OPENSSL_TARGET="mingw"
  MINGW_PREFIX="/mingw32"
  RC_TARGET="pe-i386"
else
  echo "Arch must be x64 or x86" >&2
  exit 1
fi

# Prefer MSYS tools + matching MinGW bin; keep Windows SDK rc.exe off the search path for CMake.
export PATH="${MINGW_PREFIX}/bin:/usr/bin:/bin"
hash -r || true

CC_BIN="${MINGW_PREFIX}/bin/gcc.exe"
CXX_BIN="${MINGW_PREFIX}/bin/g++.exe"
RC_BIN="${MINGW_PREFIX}/bin/windres.exe"
AR_BIN="${MINGW_PREFIX}/bin/ar.exe"
RANLIB_BIN="${MINGW_PREFIX}/bin/ranlib.exe"
CMAKE_BIN="${MINGW_PREFIX}/bin/cmake.exe"
NINJA_BIN="${MINGW_PREFIX}/bin/ninja.exe"

for t in "${CC_BIN}" "${RC_BIN}" "${CMAKE_BIN}" "${NINJA_BIN}"; do
  if [[ ! -x "${t}" ]]; then
    echo "missing toolchain: ${t}" >&2
    exit 1
  fi
done

echo "perl=$(command -v perl) gcc=${CC_BIN} windres=${RC_BIN} arch=${ARCH} target=${OPENSSL_TARGET}"
perl -v | head -2
"${CC_BIN}" -dumpmachine
"${RC_BIN}" --version | head -1

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="${ROOT}/dist/windows-mingw-${ARCH}-${LINK_TYPE}"
fi

mkdir -p "${SRC}" "${STAGE}" "${OUT_DIR}"

download() {
  local url="$1" dest="$2"
  if [[ ! -f "${dest}" ]]; then
    echo "Download ${url}"
    command -v curl >/dev/null && curl -fsSL -o "${dest}" "${url}" || wget -O "${dest}" "${url}"
  fi
}

# --- OpenSSL ---
SSL_TAG="openssl-${OPENSSL_VERSION}"
SSL_ZIP="${WORK}/${SSL_TAG}.tar.gz"
SSL_SRC="${SRC}/${SSL_TAG}"
download "https://github.com/openssl/openssl/releases/download/${SSL_TAG}/${SSL_TAG}.tar.gz" "${SSL_ZIP}"
if [[ ! -d "${SSL_SRC}" ]]; then
  tar -xzf "${SSL_ZIP}" -C "${SRC}"
fi

PREFIX_SSL="${STAGE}/openssl"
rm -rf "${PREFIX_SSL}"
mkdir -p "${PREFIX_SSL}"
pushd "${SSL_SRC}" >/dev/null
make distclean >/dev/null 2>&1 || true
# Force GNU windres (OpenSSL also honors WINDRES)
export CC="${CC_BIN}"
export AR="${AR_BIN}"
export RANLIB="${RANLIB_BIN}"
export WINDRES="${RC_BIN}"
export RC="${RC_BIN}"
if [[ "${LINK_TYPE}" == "static" ]]; then
  ./Configure "${OPENSSL_TARGET}" no-shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
else
  ./Configure "${OPENSSL_TARGET}" shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
fi
make -j"$(nproc)"
make install_sw
popd >/dev/null

# --- curl (+ curl.exe) ---
CURL_ZIP="${WORK}/curl-${CURL_VERSION}.tar.gz"
CURL_SRC="${SRC}/curl-${CURL_VERSION}"
download "https://curl.se/download/curl-${CURL_VERSION}.tar.gz" "${CURL_ZIP}"
if [[ ! -d "${CURL_SRC}" ]]; then
  tar -xzf "${CURL_ZIP}" -C "${SRC}"
fi

CURL_BUILD="${WORK}/curl-build"
rm -rf "${CURL_BUILD}"
mkdir -p "${CURL_BUILD}"
PREFIX_CURL="${STAGE}/curl"

SHARED=OFF
STATIC=ON
if [[ "${LINK_TYPE}" == "shared" ]]; then
  SHARED=ON
  STATIC=OFF
fi

# ws2_32 must come AFTER static libcrypto (GNU ld left-to-right). CMake often
# puts -lws2_32 too early; append via linker flags so curl.exe / DLLs link.
WINLIBS="-lws2_32 -lcrypt32 -lbcrypt -ladvapi32 -lgdi32 -luser32"

"${CMAKE_BIN}" -S "${CURL_SRC}" -B "${CURL_BUILD}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX_CURL}" \
  -DCMAKE_PREFIX_PATH="${PREFIX_SSL}" \
  -DCMAKE_C_COMPILER="${CC_BIN}" \
  -DCMAKE_CXX_COMPILER="${CXX_BIN}" \
  -DCMAKE_RC_COMPILER="${RC_BIN}" \
  -DCMAKE_AR="${AR_BIN}" \
  -DCMAKE_RANLIB="${RANLIB_BIN}" \
  -DCMAKE_MAKE_PROGRAM="${NINJA_BIN}" \
  -DCMAKE_RC_FLAGS="--target=${RC_TARGET}" \
  -DCMAKE_EXE_LINKER_FLAGS="${WINLIBS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${WINLIBS}" \
  -DBUILD_CURL_EXE=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DCURL_USE_OPENSSL=ON \
  -DCURL_USE_SCHANNEL=OFF \
  -DCURL_USE_LIBPSL=OFF \
  -DCURL_USE_LIBSSH2=OFF \
  -DUSE_LIBIDN2=OFF \
  -DUSE_NGHTTP2=OFF \
  -DCURL_ZLIB=OFF \
  -DCURL_BROTLI=OFF \
  -DCURL_ZSTD=OFF \
  -DCURL_DISABLE_LDAP=ON \
  -DOPENSSL_ROOT_DIR="${PREFIX_SSL}" \
  -DOPENSSL_USE_STATIC_LIBS="$([ "${LINK_TYPE}" = static ] && echo ON || echo OFF)" \
  -DBUILD_SHARED_LIBS="${SHARED}" \
  -DBUILD_STATIC_LIBS="${STATIC}"

"${CMAKE_BIN}" --build "${CURL_BUILD}" --parallel
"${CMAKE_BIN}" --install "${CURL_BUILD}"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/include" "${OUT_DIR}/lib" "${OUT_DIR}/bin" "${OUT_DIR}/share/cmake/CurlOpenSSL"
cp -a "${PREFIX_SSL}/include/." "${OUT_DIR}/include/"
cp -a "${PREFIX_CURL}/include/." "${OUT_DIR}/include/"
# OpenSSL 3 may install to lib or lib64
cp -a "${PREFIX_SSL}/lib/." "${OUT_DIR}/lib/" 2>/dev/null || true
cp -a "${PREFIX_SSL}/lib64/." "${OUT_DIR}/lib/" 2>/dev/null || true
cp -a "${PREFIX_CURL}/lib/." "${OUT_DIR}/lib/" 2>/dev/null || true
cp -a "${PREFIX_SSL}/bin/"*.dll "${OUT_DIR}/bin/" 2>/dev/null || true
cp -a "${PREFIX_CURL}/bin/"* "${OUT_DIR}/bin/" 2>/dev/null || true

if [[ ! -f "${OUT_DIR}/bin/curl.exe" ]]; then
  found="$(find "${PREFIX_CURL}" "${CURL_BUILD}" -name curl.exe 2>/dev/null | head -1 || true)"
  if [[ -n "${found}" ]]; then
    cp -f "${found}" "${OUT_DIR}/bin/curl.exe"
  else
    echo "curl.exe missing" >&2
    exit 1
  fi
fi

cp "${ROOT}/cmake/CurlOpenSSLConfig.cmake" "${OUT_DIR}/share/cmake/CurlOpenSSL/"
cat > "${OUT_DIR}/VERSION.txt" <<EOF
curl=${CURL_VERSION}
openssl=${OPENSSL_VERSION}
toolchain=mingw
arch=${ARCH}
link=${LINK_TYPE}
tools=curl.exe
mingw_prefix=${MINGW_PREFIX}
EOF
cp "${CURL_SRC}/COPYING" "${OUT_DIR}/LICENSE-curl" 2>/dev/null || true
cp "${SSL_SRC}/LICENSE.txt" "${OUT_DIR}/LICENSE-openssl" 2>/dev/null || true

echo "Staged ${OUT_DIR}"
ls -la "${OUT_DIR}/bin"
ls -la "${OUT_DIR}/lib" | head -40
