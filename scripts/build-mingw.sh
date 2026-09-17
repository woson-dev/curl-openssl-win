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
  export PATH="/usr/bin:/mingw64/bin:${PATH:-}"
  OPENSSL_TARGET="mingw64"
  MINGW_PREFIX="/mingw64"
elif [[ "${ARCH}" == "x86" ]]; then
  export PATH="/usr/bin:/mingw32/bin:${PATH:-}"
  OPENSSL_TARGET="mingw"
  MINGW_PREFIX="/mingw32"
else
  echo "Arch must be x64 or x86" >&2
  exit 1
fi

hash -r || true
echo "perl=$(command -v perl) arch=${ARCH} target=${OPENSSL_TARGET}"
perl -v | head -2

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
if [[ "${LINK_TYPE}" == "static" ]]; then
  ./Configure "${OPENSSL_TARGET}" no-shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
else
  ./Configure "${OPENSSL_TARGET}" shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
fi
make -j"$(nproc)"
make install_sw
popd >/dev/null

# --- curl (+ curl.exe) ---
CURL_TAG="curl-${CURL_VERSION//./_}"
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

cmake -S "${CURL_SRC}" -B "${CURL_BUILD}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX_CURL}" \
  -DCMAKE_PREFIX_PATH="${PREFIX_SSL}" \
  -DBUILD_CURL_EXE=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DCURL_USE_OPENSSL=ON \
  -DCURL_USE_SCHANNEL=OFF \
  -DCURL_USE_LIBPSL=OFF \
  -DUSE_NGHTTP2=OFF \
  -DCURL_DISABLE_LDAP=ON \
  -DOPENSSL_ROOT_DIR="${PREFIX_SSL}" \
  -DBUILD_SHARED_LIBS="${SHARED}" \
  -DBUILD_STATIC_LIBS="${STATIC}"

cmake --build "${CURL_BUILD}"
cmake --install "${CURL_BUILD}"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/include" "${OUT_DIR}/lib" "${OUT_DIR}/bin" "${OUT_DIR}/share/cmake/CurlOpenSSL"
cp -a "${PREFIX_SSL}/include/." "${OUT_DIR}/include/"
cp -a "${PREFIX_CURL}/include/." "${OUT_DIR}/include/"
cp -a "${PREFIX_SSL}/lib/." "${OUT_DIR}/lib/" 2>/dev/null || true
cp -a "${PREFIX_CURL}/lib/." "${OUT_DIR}/lib/" 2>/dev/null || true
cp -a "${PREFIX_SSL}/bin/"*.dll "${OUT_DIR}/bin/" 2>/dev/null || true
cp -a "${PREFIX_CURL}/bin/"* "${OUT_DIR}/bin/" 2>/dev/null || true

# Prefer installed curl.exe; fall back to build tree
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
