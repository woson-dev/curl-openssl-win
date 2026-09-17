# Build OpenSSL + libcurl + curl.exe (MSVC).
# Usage (Developer PowerShell / GHA after vcvars for the target arch):
#   .\scripts\build-msvc.ps1 -Arch x64 -LinkType static
#   .\scripts\build-msvc.ps1 -Arch x86 -LinkType shared

param(
  [ValidateSet("x64", "x86")]
  [string]$Arch = "x64",
  [ValidateSet("static", "shared")]
  [string]$LinkType = "static",
  [string]$CurlVersion = $(if ($env:CURL_VERSION) { $env:CURL_VERSION } else { "8.11.1" }),
  [string]$OpenSslVersion = $(if ($env:OPENSSL_VERSION) { $env:OPENSSL_VERSION } else { "3.3.2" }),
  [string]$WorkDir = "",
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) { $WorkDir = Join-Path $Root "build\msvc-$Arch-$LinkType" }
if (-not $OutDir) { $OutDir = Join-Path $Root "dist\windows-msvc-$Arch-$LinkType" }

New-Item -ItemType Directory -Force -Path $WorkDir, $OutDir | Out-Null
$src = Join-Path $WorkDir "src"
$stage = Join-Path $WorkDir "stage"
New-Item -ItemType Directory -Force -Path $src, $stage | Out-Null

function Get-Zip($Url, $Dest) {
  Write-Host "Download $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

$sslTarget = if ($Arch -eq "x64") { "VC-WIN64A" } else { "VC-WIN32" }
Write-Host "MSVC Arch=$Arch OpenSSL=$sslTarget LinkType=$LinkType"

# --- OpenSSL ---
$sslTag = "openssl-$OpenSslVersion"
$sslZip = Join-Path $WorkDir "$sslTag.zip"
$sslSrc = Join-Path $src $sslTag
if (-not (Test-Path $sslSrc)) {
  Get-Zip "https://github.com/openssl/openssl/archive/refs/tags/$sslTag.zip" $sslZip
  Expand-Archive -Path $sslZip -DestinationPath $src -Force
  $extracted = Get-ChildItem $src -Directory | Where-Object { $_.Name -like "openssl-*" } | Select-Object -First 1
  if ($extracted.FullName -ne $sslSrc) {
    if (Test-Path $sslSrc) { Remove-Item -Recurse -Force $sslSrc }
    Rename-Item $extracted.FullName $sslSrc
  }
}

Push-Location $sslSrc
$prefixSsl = Join-Path $stage "openssl"
New-Item -ItemType Directory -Force -Path $prefixSsl | Out-Null
# Fresh build tree per arch/link
if (Test-Path "makefile") { nmake clean 2>$null | Out-Null }
Remove-Item -Force makefile, Makefile -ErrorAction SilentlyContinue
if ($LinkType -eq "static") {
  perl Configure $sslTarget no-shared no-tests --prefix="$prefixSsl" --openssldir="$prefixSsl\ssl"
} else {
  perl Configure $sslTarget shared no-tests --prefix="$prefixSsl" --openssldir="$prefixSsl\ssl"
}
if ($LASTEXITCODE -ne 0) { throw "OpenSSL Configure failed" }
nmake
if ($LASTEXITCODE -ne 0) { throw "OpenSSL nmake failed" }
nmake install_sw
if ($LASTEXITCODE -ne 0) { throw "OpenSSL install_sw failed" }
Pop-Location

# --- curl (+ curl.exe) ---
$curlTag = "curl-$($CurlVersion.Replace('.','_'))"
$curlZip = Join-Path $WorkDir "curl-$CurlVersion.zip"
$curlSrc = Join-Path $src "curl-$CurlVersion"
if (-not (Test-Path $curlSrc)) {
  Get-Zip "https://github.com/curl/curl/releases/download/$curlTag/curl-$CurlVersion.zip" $curlZip
  Expand-Archive -Path $curlZip -DestinationPath $src -Force
}

$curlBuild = Join-Path $WorkDir "curl-build"
if (Test-Path $curlBuild) { Remove-Item -Recurse -Force $curlBuild }
New-Item -ItemType Directory -Force -Path $curlBuild | Out-Null

$shared = if ($LinkType -eq "shared") { "ON" } else { "OFF" }
$static = if ($LinkType -eq "static") { "ON" } else { "OFF" }
$prefixCurl = Join-Path $stage "curl"

$cmakeArgs = @(
  "-S", $curlSrc,
  "-B", $curlBuild,
  "-G", "Ninja",
  "-DCMAKE_BUILD_TYPE=Release",
  "-DCMAKE_INSTALL_PREFIX=$prefixCurl",
  "-DBUILD_CURL_EXE=ON",
  "-DBUILD_TESTING=OFF",
  "-DBUILD_EXAMPLES=OFF",
  "-DCURL_USE_OPENSSL=ON",
  "-DCURL_USE_SCHANNEL=OFF",
  "-DCURL_USE_LIBPSL=OFF",
  "-DUSE_NGHTTP2=OFF",
  "-DCURL_DISABLE_LDAP=ON",
  "-DOPENSSL_ROOT_DIR=$prefixSsl",
  "-DBUILD_SHARED_LIBS=$shared",
  "-DBUILD_STATIC_LIBS=$static"
)
if ($LinkType -eq "static") {
  $cmakeArgs += "-DCURL_STATIC_CRT=ON"
}

cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "cmake configure curl failed" }
cmake --build $curlBuild --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake build curl failed" }
cmake --install $curlBuild --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake install curl failed" }

# --- Assemble OutDir ---
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path `
  (Join-Path $OutDir "include"),
  (Join-Path $OutDir "lib"),
  (Join-Path $OutDir "bin"),
  (Join-Path $OutDir "share\cmake\CurlOpenSSL") | Out-Null

Copy-Item -Recurse -Force (Join-Path $prefixSsl "include\*") (Join-Path $OutDir "include")
Copy-Item -Recurse -Force (Join-Path $prefixCurl "include\*") (Join-Path $OutDir "include")

Get-ChildItem (Join-Path $prefixSsl "lib") -File -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $OutDir "lib") -Force
Get-ChildItem (Join-Path $prefixCurl "lib") -File -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $OutDir "lib") -Force
Get-ChildItem (Join-Path $prefixSsl "bin") -Filter "*.dll" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $OutDir "bin") -Force
Get-ChildItem (Join-Path $prefixCurl "bin") -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $OutDir "bin") -Force

# Ensure curl.exe is present (install may put it under bin)
$curlExe = Get-ChildItem -Path $prefixCurl, $curlBuild -Recurse -Filter "curl.exe" -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($curlExe) {
  Copy-Item -Force $curlExe.FullName (Join-Path $OutDir "bin\curl.exe")
} else {
  throw "curl.exe not found after build"
}

$libDir = Join-Path $OutDir "lib"
if (-not (Test-Path (Join-Path $libDir "libcurl.lib"))) {
  $cand = @("libcurl_a.lib", "curl.lib") | ForEach-Object { Join-Path $libDir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($cand) { Copy-Item $cand (Join-Path $libDir "libcurl.lib") -Force }
}

Copy-Item (Join-Path $Root "cmake\CurlOpenSSLConfig.cmake") (Join-Path $OutDir "share\cmake\CurlOpenSSL\CurlOpenSSLConfig.cmake") -Force
@"
curl=$CurlVersion
openssl=$OpenSslVersion
toolchain=msvc
arch=$Arch
link=$LinkType
tools=curl.exe
"@ | Set-Content -Encoding ascii (Join-Path $OutDir "VERSION.txt")

Copy-Item (Join-Path $curlSrc "COPYING") (Join-Path $OutDir "LICENSE-curl") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $sslSrc "LICENSE.txt") (Join-Path $OutDir "LICENSE-openssl") -ErrorAction SilentlyContinue

Write-Host "Staged $OutDir (curl.exe + libs)"
Get-ChildItem (Join-Path $OutDir "bin") | Select-Object Name, Length
Get-ChildItem (Join-Path $OutDir "lib") | Select-Object Name, Length
