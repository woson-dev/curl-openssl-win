# curl-openssl-win

Windows **libcurl + OpenSSL + curl.exe** 预编译包，供 `rim-agent` 及其他项目使用。

## 产物矩阵

每个组合都会生成：

1. **SDK zip**：`curl-openssl-<curl>-openssl-<ssl>-windows-<tc>-<arch>-<link>.zip`  
   - `include/` `lib/` `bin/curl.exe`（shared 另含 DLL）+ CMake 包  
2. **Tools zip**：`curl-<curl>-openssl-<ssl>-windows-<tc>-<arch>-<link>-tools.zip`  
   - 仅 `bin/`（standalone CLI，方便单独拷贝使用）

| 工具链 | 架构 | 链接 |
|--------|------|------|
| `msvc` | `x64` / `x86` | `static` / `shared` |
| `mingw` | `x64` / `x86` | `static` / `shared` |

默认版本：curl **8.11.1** + OpenSSL **3.3.2**。

## 单独使用 curl.exe

解压任意 `*-tools.zip`（或 SDK 的 `bin/`）：

```bat
curl.exe -V
curl.exe https://example.com/
```

- **static**：通常只要一个 `curl.exe`  
- **shared**：需同目录的 `libcurl*.dll` / `libssl*.dll` / `libcrypto*.dll`

## CMake 消费（SDK zip）

```cmake
set(CurlOpenSSL_ROOT "C:/deps/curl-openssl-windows-msvc-x64-static")
list(APPEND CMAKE_PREFIX_PATH "${CurlOpenSSL_ROOT}")
find_package(CurlOpenSSL REQUIRED)
target_link_libraries(myapp PRIVATE CurlOpenSSL::curl)  # alias: CURL::libcurl
```

环境变量：`CURL_OPENSSL_ROOT` / `MED_CURL_OPENSSL_ROOT`。

## 本地构建

```powershell
# MSVC x86 static（先 vcvars32 / msvc-dev-cmd arch=x86）
.\scripts\build-msvc.ps1 -Arch x86 -LinkType static

# MinGW x64（MSYS2 MINGW64）
./scripts/build-mingw.sh static x64
./scripts/build-mingw.sh shared x86
```

## 触发 CI

Push tag `v*` 或 `workflow_dispatch`。
