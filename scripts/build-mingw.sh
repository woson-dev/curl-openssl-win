#!/usr/bin/env bash
# Build OpenSSL + libcurl with MinGW-w64 (MSYS2).
# Usage:
#   ./scripts/build-mingw.sh static /path/out
#   ./scripts/build-mingw.sh shared /path/out
set -euo pipefail

LINK_TYPE="${1:-static}"
OUT_DIR="${2:-}"
CURL_VERSION="${CURL_VERSION:-8.11.1}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/build/mingw-${LINK_TYPE}"
SRC="${WORK}/src"
STAGE="${WORK}/stage"

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="${ROOT}/dist/windows-mingw-x64-${LINK_TYPE}"
fi

mkdir -p "${SRC}" "${STAGE}" "${OUT_DIR}"

download() {
  local url="$1" dest="$2"
  if [[ ! -f "${dest}" ]]; then
    echo "Download ${url}"
    curl -fsSL -o "${dest}" "${url}"
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
if [[ "${LINK_TYPE}" == "static" ]]; then
  ./Configure mingw64 no-shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
else
  ./Configure mingw64 shared no-tests --prefix="${PREFIX_SSL}" --openssldir="${PREFIX_SSL}/ssl"
fi
make -j"$(nproc)"
make install_sw
popd >/dev/null

# --- curl ---
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
  -DBUILD_CURL_EXE=OFF \
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
cp -a "${PREFIX_CURL}/bin/"*.dll "${OUT_DIR}/bin/" 2>/dev/null || true

# Ensure libcurl.a name for static
if [[ ! -f "${OUT_DIR}/lib/libcurl.a" && -f "${OUT_DIR}/lib/libcurl.dll.a" && "${LINK_TYPE}" == "static" ]]; then
  true
fi

cp "${ROOT}/cmake/CurlOpenSSLConfig.cmake" "${OUT_DIR}/share/cmake/CurlOpenSSL/"
cat > "${OUT_DIR}/VERSION.txt" <<EOF
curl=${CURL_VERSION}
openssl=${OPENSSL_VERSION}
toolchain=mingw
arch=x64
link=${LINK_TYPE}
EOF
cp "${CURL_SRC}/COPYING" "${OUT_DIR}/LICENSE-curl" 2>/dev/null || true
cp "${SSL_SRC}/LICENSE.txt" "${OUT_DIR}/LICENSE-openssl" 2>/dev/null || true

echo "Staged ${OUT_DIR}"
find "${OUT_DIR}" -maxdepth 3 -type f | head -80
